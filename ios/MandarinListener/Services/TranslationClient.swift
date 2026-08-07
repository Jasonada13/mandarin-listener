import Foundation
import MandarinListenerCore

struct TranslationClientError: LocalizedError, Sendable {
    let code: String
    let message: String
    let retryable: Bool

    var errorDescription: String? { message }
}

actor TranslationClient {
    private struct KimiPreviewChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta
        }

        let choices: [Choice]
    }

    private let relayURL: URL
    private let clientToken: String
    private let session: URLSession

    init(relayURL: URL, clientToken: String) {
        self.relayURL = relayURL
        self.clientToken = clientToken

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        session = URLSession(configuration: configuration)
    }

    func translate(_ input: TranslationRequest) async throws -> TranslationResponse {
        let clock = ContinuousClock()
        let startedAt = clock.now
        var latestError: Error?

        for attempt in 0..<2 {
            do {
                return try await performTranslation(input)
            } catch let error as TranslationClientError {
                latestError = error
                let elapsed = startedAt.duration(to: clock.now)
                guard attempt == 0, error.retryable, elapsed < .seconds(4.5) else {
                    throw error
                }
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                latestError = error
                guard attempt == 0 else { throw error }
                try await Task.sleep(for: .milliseconds(250))
            }
        }

        throw latestError ?? TranslationClientError(
            code: "translation_failed",
            message: "Translation failed.",
            retryable: true
        )
    }

    func streamPreview(
        _ input: TranslationRequest,
        onUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        let endpoint = relayURL
            .appending(path: "v1")
            .appending(path: "translate")
            .appending(path: "preview")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(input)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationClientError(
                code: "invalid_response",
                message: "The relay returned an invalid preview response.",
                retryable: true
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count >= 65_536 { break }
            }
            if let envelope = try? JSONDecoder().decode(
                RelayErrorEnvelope.self,
                from: errorData
            ) {
                throw TranslationClientError(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    retryable: envelope.error.retryable
                )
            }
            throw TranslationClientError(
                code: "preview_failed",
                message: "Live translation preview is temporarily unavailable.",
                retryable: httpResponse.statusCode == 429 || httpResponse.statusCode >= 500
            )
        }

        var accumulated = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(KimiPreviewChunk.self, from: data),
                  let content = chunk.choices.first?.delta.content,
                  !content.isEmpty
            else {
                continue
            }
            accumulated += content
            let visibleText = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
            if !visibleText.isEmpty {
                await onUpdate(visibleText)
            }
        }

        let result = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw TranslationClientError(
                code: "empty_preview",
                message: "Kimi returned an empty live translation preview.",
                retryable: true
            )
        }
        return result
    }

    private func performTranslation(
        _ input: TranslationRequest
    ) async throws -> TranslationResponse {
        let endpoint = relayURL
            .appending(path: "v1")
            .appending(path: "translate")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(input)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationClientError(
                code: "invalid_response",
                message: "The relay returned an invalid response.",
                retryable: true
            )
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let envelope = try? JSONDecoder().decode(RelayErrorEnvelope.self, from: data) {
                throw TranslationClientError(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    retryable: envelope.error.retryable
                )
            }
            throw TranslationClientError(
                code: "relay_error",
                message: "The relay could not translate this phrase.",
                retryable: httpResponse.statusCode == 429 || httpResponse.statusCode >= 500
            )
        }
        return try JSONDecoder().decode(TranslationResponse.self, from: data)
    }
}
