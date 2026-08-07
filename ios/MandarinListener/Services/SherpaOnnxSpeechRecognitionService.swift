import Foundation
import MandarinListenerCore

actor SherpaOnnxSpeechRecognitionService: RecognitionService {
    private static let modelName =
        "sherpa-onnx-streaming-zipformer-zh-int8-2025-06-30"

    private let events: AsyncStream<RecognitionEvent>
    private let eventContinuation: AsyncStream<RecognitionEvent>.Continuation

    private var vocabulary: [String]
    private var recognizer: SherpaOnnxStreamingRecognizer?
    private var segmentID = SherpaOnnxSpeechRecognitionService.newSegmentID()
    private var partialText = ""
    private var speechIsActive = false
    private var started = false
    private var stopped = false

    init(vocabulary: [String] = []) {
        self.vocabulary = Array(
            vocabulary.prefix(VocabularyLearner.onDeviceTermLimit)
        )
        let pair = AsyncStream.makeStream(of: RecognitionEvent.self)
        events = pair.stream
        eventContinuation = pair.continuation
    }

    func eventStream() -> AsyncStream<RecognitionEvent> {
        events
    }

    func prepare() throws {
        recognizer = try SherpaOnnxStreamingRecognizer(
            paths: Self.modelPaths(),
            hotwords: vocabulary
        )
    }

    func start() throws {
        guard recognizer != nil else {
            throw RecognitionServiceError.unavailable
        }
        started = true
        eventContinuation.yield(.ready)
    }

    func ingest(_ frame: AudioFrame) {
        guard started, !stopped, let recognizer else { return }
        let samples = Self.floatSamples(from: frame.pcm16)
        guard !samples.isEmpty else { return }

        recognizer.accept(samples: samples)
        recognizer.decodeAvailableAudio()
        publishCurrentResult(from: recognizer)

        guard recognizer.isEndpoint() else { return }
        finalizeCurrentSegment()
        do {
            try recognizer.reset(hotwords: vocabulary)
        } catch {
            emitError(error)
        }
    }

    func updateVocabulary(_ terms: [String]) {
        vocabulary = Array(terms.prefix(VocabularyLearner.onDeviceTermLimit))
        guard let recognizer, !speechIsActive else { return }
        do {
            try recognizer.reset(hotwords: vocabulary)
        } catch {
            emitError(error)
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true

        if let recognizer {
            recognizer.finishInput()
            publishCurrentResult(from: recognizer)
            finalizeCurrentSegment()
        }
        recognizer = nil
        eventContinuation.yield(.finished)
        eventContinuation.finish()
    }

    private func publishCurrentResult(
        from recognizer: SherpaOnnxStreamingRecognizer
    ) {
        let text = recognizer.resultText().trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty, text != partialText else { return }

        if !speechIsActive {
            speechIsActive = true
            eventContinuation.yield(.speechStarted(segmentID: segmentID))
        }
        partialText = text
        eventContinuation.yield(
            .partial(segmentID: segmentID, text: text)
        )
    }

    private func finalizeCurrentSegment() {
        guard speechIsActive else {
            partialText = ""
            segmentID = Self.newSegmentID()
            return
        }

        eventContinuation.yield(.speechStopped(segmentID: segmentID))
        if !partialText.isEmpty {
            eventContinuation.yield(
                .final(segmentID: segmentID, text: partialText)
            )
        }
        partialText = ""
        speechIsActive = false
        segmentID = Self.newSegmentID()
    }

    private func emitError(_ error: Error) {
        eventContinuation.yield(
            .error(
                code: "sherpa_onnx_error",
                message: error.localizedDescription,
                retryable: true
            )
        )
    }

    private static func modelPaths() throws -> SherpaOnnxModelPaths {
        let directory = Bundle.main.resourceURL?
            .appending(path: "SpeechModels", directoryHint: .isDirectory)
            .appending(path: modelName, directoryHint: .isDirectory)

        func path(_ name: String, extension fileExtension: String) throws -> String {
            if let directory {
                let candidate = directory.appending(
                    path: "\(name).\(fileExtension)"
                )
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate.path
                }
            }
            guard let fallback = Bundle.main.url(
                forResource: name,
                withExtension: fileExtension
            ) else {
                throw SherpaOnnxRecognizerError.modelMissing(
                    "\(name).\(fileExtension)"
                )
            }
            return fallback.path
        }

        return try SherpaOnnxModelPaths(
            encoder: path("encoder.int8", extension: "onnx"),
            decoder: path("decoder", extension: "onnx"),
            joiner: path("joiner.int8", extension: "onnx"),
            tokens: path("tokens", extension: "txt")
        )
    }

    private static func floatSamples(from pcm16: Data) -> [Float] {
        pcm16.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return []
            }
            let sampleCount = rawBuffer.count / MemoryLayout<Int16>.size
            var samples = [Float]()
            samples.reserveCapacity(sampleCount)

            for index in 0..<sampleCount {
                let offset = index * 2
                let bitPattern = UInt16(bytes[offset])
                    | (UInt16(bytes[offset + 1]) << 8)
                let sample = Int16(bitPattern: bitPattern)
                samples.append(Float(sample) / 32_768)
            }
            return samples
        }
    }

    private static func newSegmentID() -> String {
        "sherpa-\(UUID().uuidString)"
    }
}
