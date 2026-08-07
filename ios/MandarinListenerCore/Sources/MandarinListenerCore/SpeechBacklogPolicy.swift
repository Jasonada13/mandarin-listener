import Foundation

public struct SpeechBacklogDecision: Equatable, Sendable {
    public let dropPending: Bool
    public let interruptCurrentAtWordBoundary: Bool

    public init(dropPending: Bool, interruptCurrentAtWordBoundary: Bool) {
        self.dropPending = dropPending
        self.interruptCurrentAtWordBoundary = interruptCurrentAtWordBoundary
    }
}

public struct SpeechBacklogPolicy: Sendable {
    public let maximumBacklog: TimeInterval

    public init(maximumBacklog: TimeInterval = 5) {
        self.maximumBacklog = maximumBacklog
    }

    public func estimateDuration(for text: String, wordsPerMinute: Double = 210) -> TimeInterval {
        let wordCount = max(1, text.split(whereSeparator: \.isWhitespace).count)
        return max(0.8, Double(wordCount) / wordsPerMinute * 60)
    }

    public func decision(
        currentUtteranceAge: TimeInterval?,
        pendingDurations: [TimeInterval],
        newDuration: TimeInterval
    ) -> SpeechBacklogDecision {
        let queuedDuration = pendingDurations.reduce(0, +) + newDuration
        let exceedsLimit = queuedDuration > maximumBacklog
        _ = currentUtteranceAge

        return SpeechBacklogDecision(
            dropPending: exceedsLimit,
            interruptCurrentAtWordBoundary: false
        )
    }
}
