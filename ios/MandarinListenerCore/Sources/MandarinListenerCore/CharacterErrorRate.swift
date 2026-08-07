import Foundation

public enum CharacterErrorRate {
    public static func calculate(reference: String, hypothesis: String) -> Double {
        let referenceCharacters = Array(normalize(reference))
        let hypothesisCharacters = Array(normalize(hypothesis))
        guard !referenceCharacters.isEmpty else {
            return hypothesisCharacters.isEmpty ? 0 : 1
        }

        var previous = Array(0...hypothesisCharacters.count)
        for (referenceIndex, referenceCharacter) in referenceCharacters.enumerated() {
            var current = Array(repeating: 0, count: hypothesisCharacters.count + 1)
            current[0] = referenceIndex + 1

            for (hypothesisIndex, hypothesisCharacter) in hypothesisCharacters.enumerated() {
                let substitutionCost = referenceCharacter == hypothesisCharacter ? 0 : 1
                current[hypothesisIndex + 1] = min(
                    previous[hypothesisIndex + 1] + 1,
                    current[hypothesisIndex] + 1,
                    previous[hypothesisIndex] + substitutionCost
                )
            }
            previous = current
        }

        return Double(previous[hypothesisCharacters.count]) / Double(referenceCharacters.count)
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}
