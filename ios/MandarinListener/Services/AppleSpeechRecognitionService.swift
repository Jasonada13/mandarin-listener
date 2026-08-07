@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import MandarinListenerCore
@preconcurrency import Speech

#if compiler(>=6.2)
private final class SpeechAnalyzerBufferConverter {
    private let analyzerFormat: AVAudioFormat
    private var audioConverter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var outputCapacity: AVAudioFrameCount = 4_096

    init(analyzerFormat: AVAudioFormat) {
        self.analyzerFormat = analyzerFormat
    }

    func convert(
        _ buffer: AVAudioPCMBuffer,
        at _: AVAudioTime?
    ) throws -> [AnalyzerInput] {
        if formatsMatch(buffer.format, analyzerFormat) {
            return [AnalyzerInput(buffer: buffer)]
        }

        let converter = try converter(for: buffer.format)
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        outputCapacity = max(
            outputCapacity,
            AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio) + 32)
        )
        guard let output = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: outputCapacity
        ) else {
            throw RecognitionServiceError.unavailable
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(
            to: output,
            error: &conversionError
        ) { _, statusPointer in
            if suppliedInput {
                statusPointer.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            statusPointer.pointee = .haveData
            return buffer
        }

        if let conversionError {
            throw conversionError
        }
        guard status != .error else {
            throw RecognitionServiceError.unavailable
        }
        guard output.frameLength > 0 else {
            return []
        }
        return [AnalyzerInput(buffer: output)]
    }

    func flush() throws -> [AnalyzerInput] {
        guard let audioConverter else { return [] }
        var inputs: [AnalyzerInput] = []

        for _ in 0..<8 {
            guard let output = AVAudioPCMBuffer(
                pcmFormat: analyzerFormat,
                frameCapacity: outputCapacity
            ) else {
                throw RecognitionServiceError.unavailable
            }

            var conversionError: NSError?
            let status = audioConverter.convert(
                to: output,
                error: &conversionError
            ) { _, statusPointer in
                statusPointer.pointee = .endOfStream
                return nil
            }

            if let conversionError {
                throw conversionError
            }
            guard status != .error else {
                throw RecognitionServiceError.unavailable
            }
            if output.frameLength > 0 {
                inputs.append(AnalyzerInput(buffer: output))
            }
            if status == .endOfStream || output.frameLength == 0 {
                break
            }
        }

        audioConverter.reset()
        self.audioConverter = nil
        sourceFormat = nil
        return inputs
    }

    private func converter(for format: AVAudioFormat) throws -> AVAudioConverter {
        if let audioConverter,
           let sourceFormat,
           formatsMatch(sourceFormat, format) {
            return audioConverter
        }
        guard let converter = AVAudioConverter(
            from: format,
            to: analyzerFormat
        ) else {
            throw RecognitionServiceError.unavailable
        }
        sourceFormat = format
        audioConverter = converter
        return converter
    }

    private func formatsMatch(
        _ lhs: AVAudioFormat,
        _ rhs: AVAudioFormat
    ) -> Bool {
        lhs.commonFormat == rhs.commonFormat
            && lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.isInterleaved == rhs.isInterleaved
    }
}

actor AppleSpeechRecognitionService: RecognitionService {
    private enum Backend {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)
    }

    private let events: AsyncStream<RecognitionEvent>
    private let eventContinuation: AsyncStream<RecognitionEvent>.Continuation

    private var backend: Backend?
    private var analyzer: SpeechAnalyzer?
    private var converter: SpeechAnalyzerBufferConverter?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var startedSegments: Set<String> = []
    private var vocabulary: [String]

    init(vocabulary: [String] = []) {
        self.vocabulary = Array(vocabulary.prefix(VocabularyLearner.appleTermLimit))
        let pair = AsyncStream.makeStream(of: RecognitionEvent.self)
        events = pair.stream
        eventContinuation = pair.continuation
    }

    func eventStream() -> AsyncStream<RecognitionEvent> {
        events
    }

    func prepare() async throws {
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized else {
            throw RecognitionServiceError.speechPermissionDenied
        }

        if SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(
               equivalentTo: Locale(identifier: "zh-Hans")
           ) {
            do {
                try await prepareSpeechTranscriber(locale: locale)
                return
            } catch {
                backend = nil
                analyzer = nil
                converter = nil
            }
        }

        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "zh-Hans")
        ) else {
            throw RecognitionServiceError.unsupportedLocale
        }
        try await prepareDictationTranscriber(locale: locale)
    }

    func start() async throws {
        guard let analyzer, let backend else {
            throw RecognitionServiceError.unavailable
        }
        let inputPair = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = inputPair.continuation

        switch backend {
        case .speech(let transcriber):
            resultTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        await self?.handleResult(
                            text: String(result.text.characters),
                            range: result.range,
                            isFinal: result.isFinal
                        )
                    }
                } catch {
                    await self?.emitError(error)
                }
            }

        case .dictation(let transcriber):
            resultTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        await self?.handleResult(
                            text: String(result.text.characters),
                            range: result.range,
                            isFinal: result.isFinal
                        )
                    }
                } catch {
                    await self?.emitError(error)
                }
            }
        }

        analysisTask = Task { [weak self] in
            do {
                let lastSampleTime = try await analyzer.analyzeSequence(inputPair.stream)
                if let lastSampleTime {
                    try await analyzer.finalizeAndFinish(through: lastSampleTime)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                await self?.emitFinished()
            } catch {
                await self?.emitError(error)
            }
        }
        eventContinuation.yield(.ready)
    }

    func ingest(_ frame: AudioFrame) {
        guard let converter, let inputContinuation else { return }
        do {
            for input in try converter.convert(frame.buffer, at: nil) {
                inputContinuation.yield(input)
            }
        } catch {
            emitError(error)
        }
    }

    func updateVocabulary(_ terms: [String]) async {
        vocabulary = Array(terms.prefix(VocabularyLearner.appleTermLimit))
        guard let analyzer else { return }
        do {
            try await analyzer.setContext(makeAnalysisContext())
        } catch {
            // Recognition remains usable if a live context refresh is rejected.
        }
    }

    func stop() async {
        if let converter, let inputContinuation {
            do {
                for input in try converter.flush() {
                    inputContinuation.yield(input)
                }
            } catch {
                emitError(error)
            }
        }
        inputContinuation?.finish()
        _ = await analysisTask?.result
        resultTask?.cancel()
        eventContinuation.finish()
        inputContinuation = nil
        analysisTask = nil
        resultTask = nil
    }

    private func prepareSpeechTranscriber(locale: Locale) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )
        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await installationRequest.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw RecognitionServiceError.unavailable
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.setContext(makeAnalysisContext())
        try await analyzer.prepareToAnalyze(in: format)
        backend = .speech(transcriber)
        self.analyzer = analyzer
        converter = SpeechAnalyzerBufferConverter(analyzerFormat: format)
    }

    private func prepareDictationTranscriber(locale: Locale) async throws {
        let preset = DictationTranscriber.Preset.progressiveLongDictation
        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: preset.contentHints,
            transcriptionOptions: preset.transcriptionOptions,
            reportingOptions: preset.reportingOptions.union([.frequentFinalization]),
            attributeOptions: preset.attributeOptions
        )
        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await installationRequest.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw RecognitionServiceError.unavailable
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.setContext(makeAnalysisContext())
        try await analyzer.prepareToAnalyze(in: format)
        backend = .dictation(transcriber)
        self.analyzer = analyzer
        converter = SpeechAnalyzerBufferConverter(analyzerFormat: format)
    }

    private func makeAnalysisContext() -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings[.general] = vocabulary
        return context
    }

    private func handleResult(
        text rawText: String,
        range: CMTimeRange,
        isFinal: Bool
    ) {
        let seconds = CMTimeGetSeconds(range.start)
        let segmentID = "apple-\(Int(max(0, seconds) * 1_000))"
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !startedSegments.contains(segmentID) {
            startedSegments.insert(segmentID)
            eventContinuation.yield(.speechStarted(segmentID: segmentID))
        }

        if isFinal {
            eventContinuation.yield(.speechStopped(segmentID: segmentID))
            if !text.isEmpty {
                eventContinuation.yield(.final(segmentID: segmentID, text: text))
            }
            startedSegments.remove(segmentID)
        } else {
            eventContinuation.yield(.partial(segmentID: segmentID, text: text))
        }
    }

    private func emitError(_ error: Error) {
        eventContinuation.yield(
            .error(
                code: "apple_speech_error",
                message: error.localizedDescription,
                retryable: true
            )
        )
    }

    private func emitFinished() {
        eventContinuation.yield(.finished)
    }
}
#else
// Keeps non-device validation builds possible with pre-iOS-26 Xcode.
// Production builds use the SpeechAnalyzer implementation above.
actor AppleSpeechRecognitionService: RecognitionService {
    private let events: AsyncStream<RecognitionEvent>
    private let eventContinuation: AsyncStream<RecognitionEvent>.Continuation

    init(vocabulary: [String] = []) {
        let pair = AsyncStream.makeStream(of: RecognitionEvent.self)
        events = pair.stream
        eventContinuation = pair.continuation
    }

    func eventStream() -> AsyncStream<RecognitionEvent> {
        events
    }

    func prepare() throws {
        throw RecognitionServiceError.unavailable
    }

    func start() throws {
        throw RecognitionServiceError.unavailable
    }

    func ingest(_ frame: AudioFrame) {}

    func updateVocabulary(_ terms: [String]) {}

    func stop() {
        eventContinuation.finish()
    }
}
#endif
