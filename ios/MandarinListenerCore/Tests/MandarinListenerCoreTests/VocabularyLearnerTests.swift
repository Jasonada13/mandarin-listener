import Foundation
import Testing
@testable import MandarinListenerCore

@Test("Vocabulary learning derives only Chinese terms introduced by an explicit correction")
func learnsOnlyChangedChineseTerms() {
    let learner = VocabularyLearner()
    let learnedAt = Date(timeIntervalSince1970: 1_000)

    let result = learner.applyingCorrection(
        originalText: "明天去尚海见 Zhang。",
        correctedText: "明天去上海见 Jason。",
        to: [],
        at: learnedAt
    )

    #expect(result.learnedTerms == ["上海"])
    #expect(
        result.entries
            == [
                VocabularyEntry(
                    term: "上海",
                    origin: .userCorrection,
                    frequency: 1,
                    updatedAt: learnedAt
                )
            ]
    )
}

@Test("Vocabulary learning normalizes, deduplicates, increments, ranks, and caps deterministically")
func ranksAndCapsVocabulary() {
    let learner = VocabularyLearner(maximumEntries: 3)
    let baseDate = Date(timeIntervalSince1970: 1_000)
    let existing = [
        VocabularyEntry(term: "  上海。", frequency: 2, updatedAt: baseDate),
        VocabularyEntry(term: "上海", frequency: 1, updatedAt: baseDate.addingTimeInterval(1)),
        VocabularyEntry(term: "王老师", frequency: 3, updatedAt: baseDate),
        VocabularyEntry(term: "广州", frequency: 1, updatedAt: baseDate),
        VocabularyEntry(term: "深圳", frequency: 1, updatedAt: baseDate)
    ]

    let result = learner.applyingCorrection(
        originalText: "张薇今天来。",
        correctedText: "张伟今天来。",
        to: existing,
        at: baseDate.addingTimeInterval(10)
    )

    #expect(result.learnedTerms == ["伟"])
    #expect(result.entries.map(\.term) == ["上海", "王老师", "伟"])
    #expect(result.entries.map(\.frequency) == [3, 3, 1])
    #expect(learner.appleBiasTerms(from: result.entries) == ["上海", "王老师", "伟"])
    #expect(learner.onDeviceHotwords(from: result.entries) == ["上海", "王老师", "伟"])
    #expect(learner.elevenLabsKeyterms(from: result.entries) == ["上海", "王老师", "伟"])
    #expect(result.previousEntries.map(\.term) == ["上海", "王老师", "广州"])
}

@Test("Vocabulary entries round-trip through Codable")
func vocabularyCodableRoundTrip() throws {
    let entry = VocabularyEntry(
        term: "诸葛亮",
        origin: .userCorrection,
        frequency: 4,
        updatedAt: Date(timeIntervalSince1970: 42)
    )

    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(VocabularyEntry.self, from: data)

    #expect(decoded == entry)
}

@Test("Vocabulary learner rejects unchanged, empty, non-Chinese, and overlong edits")
func rejectsInvalidVocabulary() {
    let learner = VocabularyLearner()
    let overlong = String(repeating: "中", count: 21)

    #expect(
        learner.applyingCorrection(
            originalText: "上海",
            correctedText: " 上海 ",
            to: []
        ).learnedTerms.isEmpty
    )
    #expect(
        learner.applyingCorrection(
            originalText: "Zhang",
            correctedText: "Jason",
            to: []
        ).learnedTerms.isEmpty
    )
    let overlongEntry = VocabularyEntry(term: overlong)
    #expect(learner.ranked([overlongEntry], limit: 100).isEmpty)
}

@Test("A newly corrected term survives a full vocabulary store")
func retainsNewestExplicitCorrection() {
    let learner = VocabularyLearner(maximumEntries: 2)
    let existing = [
        VocabularyEntry(term: "上海", frequency: 20),
        VocabularyEntry(term: "广州", frequency: 10)
    ]

    let result = learner.applyingCorrection(
        originalText: "去深镇",
        correctedText: "去深圳",
        to: existing
    )

    #expect(result.entries.count == 2)
    #expect(result.entries.contains { $0.term == "深圳" })
    #expect(result.learnedTerms == ["深圳"])
}

@Test("Provider term lists enforce the on-device and ElevenLabs limits")
func providerTermLimits() {
    let entries = (0..<120).compactMap { offset -> VocabularyEntry? in
        guard let scalar = Unicode.Scalar(0x4E00 + offset) else {
            return nil
        }
        return VocabularyEntry(
            term: String(scalar),
            frequency: 120 - offset,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(offset))
        )
    }
    let learner = VocabularyLearner()

    #expect(learner.appleBiasTerms(from: entries).count == 100)
    #expect(learner.onDeviceHotwords(from: entries).count == 100)
    #expect(learner.elevenLabsKeyterms(from: entries).count == 50)
    #expect(
        learner.appleBiasTerms(from: entries)
            == learner.onDeviceHotwords(from: entries)
    )
    #expect(
        Array(learner.appleBiasTerms(from: entries).prefix(50))
            == learner.elevenLabsKeyterms(from: entries)
    )
}
