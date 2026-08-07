import Foundation
import NaturalLanguage

public enum VocabularyOrigin: String, Codable, Sendable {
    case userCorrection
}

public struct VocabularyEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String { term }

    public let term: String
    public let origin: VocabularyOrigin
    public let frequency: Int
    public let updatedAt: Date

    public init(
        term: String,
        origin: VocabularyOrigin = .userCorrection,
        frequency: Int = 1,
        updatedAt: Date = Date()
    ) {
        self.term = term
        self.origin = origin
        self.frequency = max(1, frequency)
        self.updatedAt = updatedAt
    }
}

public struct VocabularyLearningResult: Equatable, Sendable {
    public let entries: [VocabularyEntry]
    public let learnedTerms: [String]
    public let previousEntries: [VocabularyEntry]

    public init(
        entries: [VocabularyEntry],
        learnedTerms: [String],
        previousEntries: [VocabularyEntry]
    ) {
        self.entries = entries
        self.learnedTerms = learnedTerms
        self.previousEntries = previousEntries
    }
}

public struct VocabularyLearner: Sendable {
    public static let appleTermLimit = 100
    public static let onDeviceTermLimit = 100
    public static let elevenLabsTermLimit = 50

    public let maximumEntries: Int

    public init(maximumEntries: Int = VocabularyLearner.appleTermLimit) {
        self.maximumEntries = max(0, maximumEntries)
    }

    public func applyingCorrection(
        originalText: String,
        correctedText: String,
        to existingEntries: [VocabularyEntry],
        at date: Date = Date()
    ) -> VocabularyLearningResult {
        let previousEntries = ranked(existingEntries, limit: maximumEntries)
        let terms = introducedTerms(originalText: originalText, correctedText: correctedText)
        guard !terms.isEmpty else {
            return VocabularyLearningResult(
                entries: previousEntries,
                learnedTerms: [],
                previousEntries: previousEntries
            )
        }

        var entriesByTerm = dictionary(from: previousEntries)
        for term in terms {
            if let existing = entriesByTerm[term] {
                entriesByTerm[term] = VocabularyEntry(
                    term: term,
                    origin: .userCorrection,
                    frequency: existing.frequency + 1,
                    updatedAt: date
                )
            } else {
                entriesByTerm[term] = VocabularyEntry(
                    term: term,
                    origin: .userCorrection,
                    frequency: 1,
                    updatedAt: date
                )
            }
        }

        var retainedEntries = ranked(
            Array(entriesByTerm.values),
            limit: maximumEntries
        )
        let priorityTerms = Array(terms.prefix(maximumEntries))
        for term in priorityTerms where !retainedEntries.contains(where: { $0.term == term }) {
            if let removableIndex = retainedEntries.lastIndex(where: {
                !priorityTerms.contains($0.term)
            }) {
                retainedEntries.remove(at: removableIndex)
            }
            if let entry = entriesByTerm[term], retainedEntries.count < maximumEntries {
                retainedEntries.append(entry)
            }
        }
        retainedEntries.sort(by: ranksBefore)
        let retainedTermSet = Set(retainedEntries.map(\.term))

        return VocabularyLearningResult(
            entries: retainedEntries,
            learnedTerms: terms.filter(retainedTermSet.contains),
            previousEntries: previousEntries
        )
    }

    public func introducedTerms(originalText: String, correctedText: String) -> [String] {
        let originalTokens = chineseTokens(in: originalText)
        let correctedTokens = chineseTokens(in: correctedText)
        guard originalTokens != correctedTokens else {
            return []
        }

        var remainingOriginalCounts = originalTokens.reduce(into: [String: Int]()) {
            $0[$1, default: 0] += 1
        }
        var introduced: [String] = []
        var seen = Set<String>()

        for token in correctedTokens {
            if let count = remainingOriginalCounts[token], count > 0 {
                remainingOriginalCounts[token] = count - 1
            } else if seen.insert(token).inserted {
                introduced.append(token)
            }
        }

        return introduced
    }

    public func ranked(
        _ entries: [VocabularyEntry],
        limit: Int
    ) -> [VocabularyEntry] {
        let normalizedEntries = Array(dictionary(from: entries).values)
        return normalizedEntries
            .sorted(by: ranksBefore)
            .prefix(max(0, limit))
            .map { $0 }
    }

    public func appleBiasTerms(from entries: [VocabularyEntry]) -> [String] {
        ranked(entries, limit: Self.appleTermLimit).map(\.term)
    }

    public func onDeviceHotwords(from entries: [VocabularyEntry]) -> [String] {
        ranked(entries, limit: Self.onDeviceTermLimit).map(\.term)
    }

    public func elevenLabsKeyterms(from entries: [VocabularyEntry]) -> [String] {
        ranked(entries, limit: Self.elevenLabsTermLimit).map(\.term)
    }

    private func chineseTokens(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.simplifiedChinese)
        tokenizer.string = text

        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if let normalized = normalizeTerm(String(text[range])) {
                tokens.append(normalized)
            }
            return true
        }
        return tokens
    }

    private func dictionary(from entries: [VocabularyEntry]) -> [String: VocabularyEntry] {
        var entriesByTerm: [String: VocabularyEntry] = [:]
        for entry in entries {
            guard let normalizedTerm = normalizeTerm(entry.term) else {
                continue
            }

            if let existing = entriesByTerm[normalizedTerm] {
                entriesByTerm[normalizedTerm] = VocabularyEntry(
                    term: normalizedTerm,
                    origin: .userCorrection,
                    frequency: existing.frequency + entry.frequency,
                    updatedAt: max(existing.updatedAt, entry.updatedAt)
                )
            } else {
                entriesByTerm[normalizedTerm] = VocabularyEntry(
                    term: normalizedTerm,
                    origin: .userCorrection,
                    frequency: entry.frequency,
                    updatedAt: entry.updatedAt
                )
            }
        }
        return entriesByTerm
    }

    private func normalizeTerm(_ candidate: String) -> String? {
        let boundaries = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        let term = candidate
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: boundaries)
        guard (1...20).contains(term.count),
              term.unicodeScalars.allSatisfy(Self.isHan)
        else {
            return nil
        }
        return term
    }

    private func ranksBefore(_ lhs: VocabularyEntry, _ rhs: VocabularyEntry) -> Bool {
        if lhs.frequency != rhs.frequency {
            return lhs.frequency > rhs.frequency
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.term < rhs.term
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0x2CEB0...0x2EBEF,
             0x30000...0x3134F:
            true
        default:
            false
        }
    }
}
