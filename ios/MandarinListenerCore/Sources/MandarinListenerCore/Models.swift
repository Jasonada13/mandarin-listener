import Foundation

public enum RecognizerKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case apple
    case sherpaOnDevice
    case elevenLabs

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apple: "Apple On-Device"
        case .sherpaOnDevice: "Sherpa Local (Offline)"
        case .elevenLabs: "ElevenLabs Cloud"
        }
    }

    public var fallbackCandidates: [RecognizerKind] {
        switch self {
        case .apple:
            [.sherpaOnDevice, .elevenLabs]
        case .sherpaOnDevice:
            [.apple, .elevenLabs]
        case .elevenLabs:
            [.apple, .sherpaOnDevice]
        }
    }
}

public enum SessionPhase: Equatable, Sendable {
    case idle
    case starting
    case listening
    case reconnecting
    case paused
    case failed(String)

    public var label: String {
        switch self {
        case .idle: "Ready"
        case .starting: "Starting"
        case .listening: "Listening"
        case .reconnecting: "Reconnecting"
        case .paused: "Paused"
        case .failed: "Needs attention"
        }
    }

    public var isActive: Bool {
        switch self {
        case .starting, .listening, .reconnecting:
            true
        case .idle, .paused, .failed:
            false
        }
    }
}

public enum TranslationState: String, Codable, Sendable {
    case pending
    case translating
    case translated
    case unavailable
}

public enum SpeechState: String, Codable, Sendable {
    case pending
    case speaking
    case spoken
    case skipped
    case muted
}

public struct TranscriptEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let segmentID: String
    public var sourceText: String
    public private(set) var originalSourceText: String?
    public var displayTranslation: String?
    public var spokenTranslation: String?
    public let createdAt: Date
    public var finalizedAt: Date
    public var translationLatencyMs: Int?
    public var translationState: TranslationState
    public var speechState: SpeechState
    public private(set) var translationRevision: Int

    public init(
        id: UUID = UUID(),
        segmentID: String,
        sourceText: String,
        originalSourceText: String? = nil,
        displayTranslation: String? = nil,
        spokenTranslation: String? = nil,
        createdAt: Date = Date(),
        finalizedAt: Date = Date(),
        translationLatencyMs: Int? = nil,
        translationState: TranslationState = .pending,
        speechState: SpeechState = .pending,
        translationRevision: Int = 0
    ) {
        self.id = id
        self.segmentID = segmentID
        self.sourceText = sourceText
        self.originalSourceText = originalSourceText
        self.displayTranslation = displayTranslation
        self.spokenTranslation = spokenTranslation
        self.createdAt = createdAt
        self.finalizedAt = finalizedAt
        self.translationLatencyMs = translationLatencyMs
        self.translationState = translationState
        self.speechState = speechState
        self.translationRevision = max(0, translationRevision)
    }

    @discardableResult
    public mutating func applyUserCorrection(_ correctedText: String) -> Bool {
        let normalizedText = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty, normalizedText != sourceText else {
            return false
        }

        if originalSourceText == nil {
            originalSourceText = sourceText
        }
        sourceText = normalizedText
        displayTranslation = nil
        spokenTranslation = nil
        translationLatencyMs = nil
        translationState = .pending
        speechState = .skipped
        translationRevision += 1
        return true
    }

    public func acceptsTranslation(revision: Int) -> Bool {
        revision == translationRevision
    }

    @discardableResult
    public mutating func applyTranslation(
        display: String,
        spoken: String,
        latencyMs: Int,
        revision: Int
    ) -> Bool {
        guard acceptsTranslation(revision: revision) else {
            return false
        }

        displayTranslation = display
        spokenTranslation = spoken
        translationLatencyMs = latencyMs
        translationState = .translated
        speechState = .pending
        return true
    }
}

public enum RecognitionEvent: Equatable, Sendable {
    case ready
    case speechStarted(segmentID: String)
    case partial(segmentID: String, text: String)
    case final(segmentID: String, text: String)
    case speechStopped(segmentID: String)
    case finished
    case error(code: String, message: String, retryable: Bool)
}
