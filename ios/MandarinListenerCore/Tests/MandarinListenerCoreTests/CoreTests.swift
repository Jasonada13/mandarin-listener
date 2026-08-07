import Foundation
import Testing
@testable import MandarinListenerCore

@Test func livePreviewWaitsForEnoughMandarinAndReusesTerminalPunctuationVariants() {
    let policy = LiveTranslationPreviewPolicy(minimumSourceCharacters: 3)

    #expect(!policy.isEligible("你好"))
    #expect(policy.isEligible("你好啊"))
    #expect(policy.cacheMatches(previewSource: "我们明天去", finalSource: "我们明天去。"))
    #expect(!policy.cacheMatches(previewSource: "我们明天去", finalSource: "我们明天不去。"))
}

@Test("Context keeps only the latest eight turns from the previous 90 seconds")
func contextWindowLimitsAgeAndCount() {
    let now = Date(timeIntervalSince1970: 1_000)
    let entries = (0..<12).map { index in
        TranscriptEntry(
            segmentID: "\(index)",
            sourceText: "句子\(index)",
            finalizedAt: now.addingTimeInterval(TimeInterval(index - 10) * 10),
            translationState: .translated
        )
    }

    let context = ContextWindow.build(from: entries, now: now)

    #expect(context.count == 8)
    #expect(context.first?.sourceText == "句子4")
    #expect(context.last?.sourceText == "句子11")
}

@Test("Speech policy drops queued speech when the five second budget is exceeded")
func speechBacklogDropsStaleWork() {
    let policy = SpeechBacklogPolicy(maximumBacklog: 5)
    let decision = policy.decision(
        currentUtteranceAge: 6,
        pendingDurations: [2.5, 2],
        newDuration: 1.5
    )

    #expect(decision.dropPending)
    #expect(!decision.interruptCurrentAtWordBoundary)
}

@Test("Transcript export contains source and translated text")
func transcriptMarkdown() {
    let entry = TranscriptEntry(
        segmentID: "1",
        sourceText: "请坐。",
        displayTranslation: "Please sit down.",
        finalizedAt: Date(timeIntervalSince1970: 100),
        translationState: .translated
    )

    let markdown = TranscriptFormatter.markdown(
        entries: [entry],
        sessionStartedAt: Date(timeIntervalSince1970: 0),
        generatedAt: Date(timeIntervalSince1970: 200)
    )

    #expect(markdown.contains("请坐。"))
    #expect(markdown.contains("Please sit down."))
}

@Test("Chinese character error rate ignores punctuation and whitespace")
func characterErrorRate() {
    #expect(CharacterErrorRate.calculate(reference: "你好，世界！", hypothesis: "你好世界") == 0)
    #expect(CharacterErrorRate.calculate(reference: "你好世界", hypothesis: "你好世") == 0.25)
}

@Test("Recognizer choices expose Apple, local Sherpa, and ElevenLabs")
func recognizerChoices() {
    #expect(
        RecognizerKind.allCases
            == [.apple, .sherpaOnDevice, .elevenLabs]
    )
    #expect(
        RecognizerKind.sherpaOnDevice.displayName
            == "Sherpa Local (Offline)"
    )
    #expect(RecognizerKind.elevenLabs.displayName == "ElevenLabs Cloud")
    #expect(
        RecognizerKind.elevenLabs.fallbackCandidates
            == [.apple, .sherpaOnDevice]
    )
    #expect(
        RecognizerKind.apple.fallbackCandidates
            == [.sherpaOnDevice, .elevenLabs]
    )
}

@Test("Explicit correction invalidates stale translations and preserves the first source")
func transcriptCorrectionRevision() {
    var entry = TranscriptEntry(
        segmentID: "segment-1",
        sourceText: "明天去尚海。",
        displayTranslation: "We are going tomorrow.",
        spokenTranslation: "We're going tomorrow.",
        translationLatencyMs: 500,
        translationState: .translated,
        speechState: .speaking
    )

    let firstRevision = entry.translationRevision
    let appliedFirstCorrection = entry.applyUserCorrection("明天去上海。")
    #expect(appliedFirstCorrection)
    #expect(entry.sourceText == "明天去上海。")
    #expect(entry.originalSourceText == "明天去尚海。")
    #expect(entry.translationRevision == firstRevision + 1)
    #expect(entry.displayTranslation == nil)
    #expect(entry.spokenTranslation == nil)
    #expect(entry.translationLatencyMs == nil)
    #expect(entry.translationState == .pending)
    #expect(entry.speechState == .skipped)
    #expect(!entry.acceptsTranslation(revision: firstRevision))
    #expect(entry.acceptsTranslation(revision: firstRevision + 1))
    let appliedStaleTranslation = entry.applyTranslation(
        display: "Stale translation",
        spoken: "Stale speech",
        latencyMs: 1,
        revision: firstRevision
    )
    #expect(!appliedStaleTranslation)
    #expect(entry.displayTranslation == nil)

    let appliedSecondCorrection = entry.applyUserCorrection("明天去上海市。")
    #expect(appliedSecondCorrection)
    #expect(entry.originalSourceText == "明天去尚海。")
    let appliedDuplicateCorrection = entry.applyUserCorrection("  明天去上海市。  ")
    let appliedEmptyCorrection = entry.applyUserCorrection("   ")
    #expect(!appliedDuplicateCorrection)
    #expect(!appliedEmptyCorrection)
}
