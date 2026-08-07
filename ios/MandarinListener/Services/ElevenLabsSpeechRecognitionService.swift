import Foundation
import MandarinListenerCore

actor ElevenLabsSpeechRecognitionService: RecognitionService {
    private struct TokenResponse: Decodable {
        let token: String
        let expiresInSeconds: Int
    }

    private struct RealtimeMessage: Decodable {
        let messageType: String
        let text: String?
        let error: String?
        let errorCode: String?

        enum CodingKeys: String, CodingKey {
            case messageType = "message_type"
            case text
            case error
            case errorCode = "error_code"
        }
    }

    private struct AudioChunk: Encodable {
        let messageType = "input_audio_chunk"
        let audioBase64: String
        let commit: Bool?

        enum CodingKeys: String, CodingKey {
            case messageType = "message_type"
            case audioBase64 = "audio_base_64"
            case commit
        }
    }

    private static let bytesPerChunk = 3_200 // 100 ms of mono 16-bit PCM at 16 kHz.

    private let relayURL: URL
    private let clientToken: String
    private let session: URLSession
    private let events: AsyncStream<RecognitionEvent>
    private let eventContinuation: AsyncStream<RecognitionEvent>.Continuation

    private var keyterms: [String]
    private var singleUseToken: String?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connectionWatchdog: Task<Void, Never>?
    private var audioBuffer = Data()
    private var segmentID =
        ElevenLabsSpeechRecognitionService.newSegmentID()
    private var speechIsActive = false
    private var receivedSessionStart = false
    private var stopped = false
    private var manualCommitPending = false

    init(
        relayURL: URL,
        clientToken: String,
        keyterms: [String]
    ) {
        self.relayURL = relayURL
        self.clientToken = clientToken
        self.keyterms = Array(keyterms.prefix(VocabularyLearner.elevenLabsTermLimit))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)

        let pair = AsyncStream.makeStream(of: RecognitionEvent.self)
        events = pair.stream
        eventContinuation = pair.continuation
    }

    func eventStream() -> AsyncStream<RecognitionEvent> {
        events
    }

    func prepare() async throws {
        guard clientToken.count >= 32 else {
            throw RecognitionServiceError.missingRelayConfiguration
        }

        let endpoint = relayURL
            .appending(path: "v1")
            .appending(path: "asr")
            .appending(path: "elevenlabs")
            .appending(path: "token")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw RecognitionServiceError.unavailable
        }
        guard (200..<300).contains(response.statusCode) else {
            if let envelope = try? JSONDecoder().decode(RelayErrorEnvelope.self, from: data) {
                throw TranslationClientError(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    retryable: envelope.error.retryable
                )
            }
            throw TranslationClientError(
                code: "elevenlabs_token_failed",
                message: "ElevenLabs could not start. Apple captions will be used.",
                retryable: true
            )
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !tokenResponse.token.isEmpty, tokenResponse.expiresInSeconds > 0 else {
            throw RecognitionServiceError.unavailable
        }
        singleUseToken = tokenResponse.token
    }

    func start() async throws {
        guard let singleUseToken else {
            throw RecognitionServiceError.unavailable
        }

        let socketURL = try makeSocketURL(token: singleUseToken)
        let socket = session.webSocketTask(with: socketURL)
        self.socket = socket
        self.singleUseToken = nil
        socket.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
        connectionWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await self?.emitConnectionTimeoutIfNeeded()
        }
    }

    func ingest(_ frame: AudioFrame) async {
        guard socket != nil, !stopped else { return }
        audioBuffer.append(frame.pcm16)

        while audioBuffer.count >= Self.bytesPerChunk {
            let chunk = audioBuffer.prefix(Self.bytesPerChunk)
            audioBuffer.removeFirst(Self.bytesPerChunk)
            do {
                try await sendAudio(Data(chunk), commit: nil)
            } catch {
                emitSocketError(error)
                return
            }
        }
    }

    func updateVocabulary(_ terms: [String]) {
        // ElevenLabs keyterms are fixed in the connection URL. Retain changes for
        // a future connection rather than pretending to update the active stream.
        keyterms = Array(terms.prefix(VocabularyLearner.elevenLabsTermLimit))
    }

    func stop() async {
        guard !stopped else { return }
        stopped = true

        manualCommitPending = true
        try? await sendAudio(audioBuffer, commit: true)
        audioBuffer.removeAll(keepingCapacity: false)
        for _ in 0..<20 {
            guard manualCommitPending else { break }
            try? await Task.sleep(for: .milliseconds(100))
        }

        socket?.cancel(with: .normalClosure, reason: nil)
        receiveTask?.cancel()
        connectionWatchdog?.cancel()
        receiveTask = nil
        connectionWatchdog = nil
        socket = nil
        eventContinuation.finish()
        session.invalidateAndCancel()
    }

    private func receiveLoop() async {
        guard let socket else { return }

        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .data(let value):
                    data = value
                case .string(let value):
                    data = Data(value.utf8)
                @unknown default:
                    continue
                }

                let event = try JSONDecoder().decode(RealtimeMessage.self, from: data)
                handle(event)
            }
        } catch where Task.isCancelled || stopped {
            return
        } catch {
            emitSocketError(error)
        }
    }

    private func handle(_ message: RealtimeMessage) {
        switch message.messageType {
        case "session_started":
            receivedSessionStart = true
            connectionWatchdog?.cancel()
            connectionWatchdog = nil
            eventContinuation.yield(.ready)

        case "partial_transcript", "final_transcript":
            let text = normalized(message.text)
            guard !text.isEmpty else { return }
            beginSpeechIfNeeded()
            eventContinuation.yield(.partial(segmentID: segmentID, text: text))

        case "committed_transcript", "committed_transcript_with_timestamps":
            let text = normalized(message.text)
            manualCommitPending = false
            guard !text.isEmpty else { return }
            beginSpeechIfNeeded()
            eventContinuation.yield(.speechStopped(segmentID: segmentID))
            eventContinuation.yield(.final(segmentID: segmentID, text: text))
            speechIsActive = false
            segmentID = Self.newSegmentID()

        case "auth_error", "quota_exceeded", "rate_limited",
             "queue_overflow", "resource_exhausted",
             "session_time_limit_exceeded", "chunk_size_exceeded",
             "insufficient_audio_activity", "transcriber_error",
             "input_error", "commit_throttled", "unaccepted_terms",
             "error":
            eventContinuation.yield(
                .error(
                    code: message.errorCode ?? message.messageType,
                    message: message.error ?? "ElevenLabs recognition failed.",
                    retryable: true
                )
            )

        default:
            break
        }
    }

    private func beginSpeechIfNeeded() {
        guard !speechIsActive else { return }
        speechIsActive = true
        eventContinuation.yield(.speechStarted(segmentID: segmentID))
    }

    private func sendAudio(_ data: Data, commit: Bool?) async throws {
        guard let socket else { return }
        let chunk = AudioChunk(
            audioBase64: data.base64EncodedString(),
            commit: commit
        )
        let encoded = try JSONEncoder().encode(chunk)
        guard let payload = String(data: encoded, encoding: .utf8) else {
            throw RecognitionServiceError.unavailable
        }
        try await socket.send(.string(payload))
    }

    private func makeSocketURL(token: String) throws -> URL {
        var components = URLComponents(
            string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
        )
        var queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "language_code", value: "zho"),
            URLQueryItem(name: "commit_strategy", value: "vad"),
            URLQueryItem(name: "vad_silence_threshold_secs", value: "0.6"),
            URLQueryItem(name: "vad_threshold", value: "0.4"),
            URLQueryItem(name: "min_speech_duration_ms", value: "100"),
            URLQueryItem(name: "min_silence_duration_ms", value: "100"),
            URLQueryItem(name: "no_verbatim", value: "false"),
            URLQueryItem(name: "filter_background_audio", value: "false")
        ]
        queryItems.append(
            contentsOf: keyterms.map {
                URLQueryItem(name: "keyterms", value: $0)
            }
        )
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw RecognitionServiceError.unavailable
        }
        return url
    }

    private func emitConnectionTimeoutIfNeeded() {
        guard !receivedSessionStart, !stopped else { return }
        eventContinuation.yield(
            .error(
                code: "elevenlabs_connection_timeout",
                message: "ElevenLabs did not become ready in time.",
                retryable: true
            )
        )
    }

    private func emitSocketError(_ error: Error) {
        guard !stopped else { return }
        eventContinuation.yield(
            .error(
                code: "elevenlabs_socket_error",
                message: error.localizedDescription,
                retryable: true
            )
        )
    }

    private func normalized(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func newSegmentID() -> String {
        "elevenlabs-\(UUID().uuidString)"
    }
}
