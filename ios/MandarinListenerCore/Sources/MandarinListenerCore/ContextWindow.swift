import Foundation

public enum ContextWindow {
    public static func build(
        from entries: [TranscriptEntry],
        now: Date = Date(),
        maximumTurns: Int = 8,
        maximumAge: TimeInterval = 90
    ) -> [TranslationContextTurn] {
        let cutoff = now.addingTimeInterval(-maximumAge)
        let formatter = ISO8601DateFormatter()

        return entries
            .filter { $0.finalizedAt >= cutoff }
            .suffix(maximumTurns)
            .map {
                TranslationContextTurn(
                    sourceText: $0.sourceText,
                    displayTranslation: $0.displayTranslation,
                    timestamp: formatter.string(from: $0.finalizedAt)
                )
            }
    }
}
