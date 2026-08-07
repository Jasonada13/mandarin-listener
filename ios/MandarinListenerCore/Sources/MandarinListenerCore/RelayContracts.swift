import Foundation

public struct TranslationContextTurn: Codable, Equatable, Sendable {
    public let sourceText: String
    public let displayTranslation: String?
    public let timestamp: String?

    public init(sourceText: String, displayTranslation: String?, timestamp: String?) {
        self.sourceText = sourceText
        self.displayTranslation = displayTranslation
        self.timestamp = timestamp
    }
}

public struct TranslationRequest: Codable, Equatable, Sendable {
    public let sessionId: String
    public let utteranceId: String
    public let sourceText: String
    public let context: [TranslationContextTurn]

    public init(
        sessionId: String,
        utteranceId: String,
        sourceText: String,
        context: [TranslationContextTurn]
    ) {
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.sourceText = sourceText
        self.context = context
    }
}

public struct TranslationResponse: Codable, Equatable, Sendable {
    public let utteranceId: String
    public let displayTranslation: String
    public let spokenTranslation: String
    public let model: String
    public let latencyMs: Int
}

public struct RelayErrorEnvelope: Decodable, Sendable {
    public struct Detail: Decodable, Sendable {
        public let code: String
        public let message: String
        public let retryable: Bool
        public let requestId: String?
    }

    public let error: Detail
}
