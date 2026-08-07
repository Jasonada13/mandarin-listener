import Foundation

public struct LiveTranslationPreviewPolicy: Sendable {
    public let minimumSourceCharacters: Int

    public init(minimumSourceCharacters: Int = 3) {
        self.minimumSourceCharacters = max(1, minimumSourceCharacters)
    }

    public func isEligible(_ sourceText: String) -> Bool {
        normalizedSource(sourceText).count >= minimumSourceCharacters
    }

    public func cacheMatches(previewSource: String, finalSource: String) -> Bool {
        comparisonKey(previewSource) == comparisonKey(finalSource)
    }

    public func normalizedSource(_ sourceText: String) -> String {
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func comparisonKey(_ sourceText: String) -> String {
        normalizedSource(sourceText)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
