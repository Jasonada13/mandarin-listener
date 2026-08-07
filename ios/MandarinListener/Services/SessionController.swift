import Combine
import Foundation
import MandarinListenerCore
import UIKit

@MainActor
final class SessionController: ObservableObject {
    private struct PreparedRecognizer {
        let kind: RecognizerKind
        let service: any RecognitionService
        let events: AsyncStream<RecognitionEvent>
    }

    @Published private(set) var phase: SessionPhase = .idle
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published private(set) var partialText = ""
    @Published private(set) var partialTranslation = ""
    @Published private(set) var isPreviewTranslating = false
    @Published private(set) var statusMessage = "Place the iPhone near the speaker."
    @Published private(set) var routeState: AudioRouteState = .unknown
    @Published private(set) var activeRecognizerKind: RecognizerKind = .apple
    @Published private(set) var sessionStartedAt = Date()
    @Published private(set) var learnedTermsNotice: [String] = []
    @Published private(set) var isNetworkAvailable = false
    @Published var isMuted = false {
        didSet { updateSpeechAvailability() }
    }
    @Published var exportURL: URL?
    @Published var isShowingSettings = false

    let settings: AppSettings
    let vocabularyStore: VocabularyStore

    private let audioCapture = AudioCaptureService()
    private let speechQueue = SpeechQueue()
    private let networkMonitor = NetworkMonitor()
    private var activeRecognizer: (any RecognitionService)?
    private var translationClient: TranslationClient?
    private var recognitionEventTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var frameContinuation: AsyncStream<AudioFrame>.Continuation?
    private var translationTasks: [UUID: Task<Void, Never>] = [:]
    private var previewTask: Task<Void, Never>?
    private var pendingPreviewText = ""
    private var previewSequence = 0
    private var lastCompletedPreviewSource = ""
    private var lastCompletedPreviewTranslation = ""
    private let previewPolicy = LiveTranslationPreviewPolicy()
    private var sessionID = UUID().uuidString
    private var attemptedRecognizers = Set<RecognizerKind>()
    private var fallbackInProgress = false
    private var lifecycleTask: Task<Void, Never>?
    private var lifecycleRevision = 0
    private var sessionIntentRevision = 0

    init(settings: AppSettings, vocabularyStore: VocabularyStore) {
        self.settings = settings
        self.vocabularyStore = vocabularyStore
        activeRecognizerKind = settings.selectedRecognizer
        TranscriptExporter.removeStaleExports()

        audioCapture.onRouteChange = { [weak self] route in
            self?.handleRouteChange(route)
        }
        audioCapture.onInterruption = { [weak self] began in
            guard began else { return }
            Task { @MainActor in
                await self?.pauseForInterruption()
            }
        }
        audioCapture.onError = { [weak self] error in
            self?.statusMessage = error.localizedDescription
        }
        speechQueue.onStateChange = { [weak self] id, state in
            self?.updateSpeechState(id: id, state: state)
        }
        vocabularyStore.onEntriesChange = { [weak self] entries in
            self?.vocabularyDidChange(entries)
        }
        networkMonitor.onChange = { [weak self] isAvailable in
            self?.isNetworkAvailable = isAvailable
        }
        networkMonitor.start()
    }

    func toggleSession() {
        sessionIntentRevision += 1
        let intentRevision = sessionIntentRevision
        if phase.isActive {
            lifecycleTask?.cancel()
            lifecycleTask = Task { [weak self] in
                await self?.stopSession(finalPhase: .idle)
            }
        } else {
            let previousTask = lifecycleTask
            let preserveTranscript = phase == .paused
            lifecycleTask = Task { [weak self] in
                _ = await previousTask?.result
                guard let self,
                      !Task.isCancelled,
                      self.sessionIntentRevision == intentRevision,
                      !self.phase.isActive
                else {
                    return
                }
                await self.startSession(clearTranscript: !preserveTranscript)
            }
        }
    }

    func startSession(clearTranscript: Bool = true) async {
        lifecycleRevision += 1
        let revision = lifecycleRevision

        if clearTranscript {
            discardTranscript()
            sessionID = UUID().uuidString
            sessionStartedAt = Date()
        }

        attemptedRecognizers.removeAll()
        fallbackInProgress = false
        phase = .starting
        statusMessage = "Preparing \(settings.selectedRecognizer.displayName)…"
        if settings.isConfigured, let relayURL = settings.relayURL {
            translationClient = TranslationClient(
                relayURL: relayURL,
                clientToken: settings.clientToken
            )
        } else {
            translationClient = nil
        }

        let framePair = AsyncStream.makeStream(
            of: AudioFrame.self,
            bufferingPolicy: .bufferingNewest(12)
        )
        frameContinuation = framePair.continuation
        audioCapture.onFrame = { frame in
            framePair.continuation.yield(frame)
        }
        let localFrameTask = Task { @MainActor [weak self] in
            for await frame in framePair.stream {
                guard let recognizer = self?.activeRecognizer else { continue }
                await recognizer.ingest(frame)
            }
        }
        frameTask = localFrameTask

        do {
            let prepared = try await preparePreferredRecognizer(
                settings.selectedRecognizer,
                revision: revision
            )
            guard isCurrentLifecycle(revision) else {
                await prepared.service.stop()
                framePair.continuation.finish()
                localFrameTask.cancel()
                return
            }
            install(prepared)

            try await audioCapture.start()
            guard isCurrentLifecycle(revision) else {
                if !phase.isActive {
                    audioCapture.stop()
                }
                await prepared.service.stop()
                framePair.continuation.finish()
                localFrameTask.cancel()
                return
            }
            routeState = audioCapture.routeState
            updateSpeechAvailability()
            UIApplication.shared.isIdleTimerDisabled = true
            phase = .listening
            statusMessage = listeningStatus()
        } catch {
            guard isCurrentLifecycle(revision) else {
                framePair.continuation.finish()
                localFrameTask.cancel()
                return
            }
            await stopSession(finalPhase: .failed(error.localizedDescription))
        }
    }

    func stopSession(finalPhase: SessionPhase = .idle) async {
        lifecycleRevision += 1
        let revision = lifecycleRevision
        phase = finalPhase
        updateSpeechAvailability()
        speechQueue.stop()
        cancelLivePreview(clearCompletedCache: true)
        audioCapture.stop()
        frameContinuation?.finish()
        frameContinuation = nil
        frameTask?.cancel()
        frameTask = nil

        let eventTask = recognitionEventTask
        let recognizer = activeRecognizer
        activeRecognizer = nil
        if let recognizer {
            await recognizer.stop()
        }
        _ = await eventTask?.result
        eventTask?.cancel()
        guard revision == lifecycleRevision else { return }

        recognitionEventTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
        partialText = ""
        partialTranslation = ""
        switch finalPhase {
        case .paused:
            statusMessage = "Audio was interrupted. Tap Resume when ready."
        case .failed(let message):
            statusMessage = message
        default:
            statusMessage = "Session stopped. Export or start a new session."
        }
    }

    func replayLast() {
        guard let entry = entries.last,
              let spokenText = entry.spokenTranslation,
              routeState.hasPrivateBluetoothOutput,
              !isMuted
        else {
            return
        }
        speechQueue.configure(
            enabled: true,
            speechRate: settings.speechRate,
            voiceIdentifier: settings.speechVoiceIdentifier
        )
        speechQueue.replay(id: entry.id, text: spokenText)
    }

    func correctCaption(id: UUID, correctedText: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let originalText = entries[index].sourceText
        let normalizedCorrection = correctedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedCorrection.isEmpty, normalizedCorrection != originalText else {
            return
        }
        let previousSpeechState = entries[index].speechState
        let speechHadStarted = speechQueue.cancel(id: id)
            || previousSpeechState == .speaking
            || previousSpeechState == .spoken

        translationTasks[id]?.cancel()
        translationTasks[id] = nil
        guard entries[index].applyUserCorrection(normalizedCorrection) else { return }

        entries[index].translationState = .translating
        entries[index].speechState = speechHadStarted ? .skipped : .pending
        let correctedEntry = entries[index]
        let context = ContextWindow.build(
            from: entries.filter {
                $0.id != id && $0.finalizedAt <= correctedEntry.finalizedAt
            }
        )

        let learnedTerms = vocabularyStore.learnFromCorrection(
            originalText: originalText,
            correctedText: correctedEntry.sourceText
        )
        learnedTermsNotice = learnedTerms

        requestTranslation(
            for: correctedEntry,
            revision: correctedEntry.translationRevision,
            context: context,
            allowsAutomaticSpeech: !speechHadStarted
        )
    }

    func undoLastVocabularyLearning() {
        vocabularyStore.undoLastLearning()
        learnedTermsNotice = []
    }

    func dismissLearnedTermsNotice() {
        learnedTermsNotice = []
    }

    func prepareExport() {
        guard !entries.isEmpty else { return }
        if let existing = exportURL {
            TranscriptExporter.removeExport(at: existing)
        }
        do {
            exportURL = try TranscriptExporter.createExport(
                entries: entries,
                sessionStartedAt: sessionStartedAt
            )
        } catch {
            statusMessage = "Could not create the transcript export."
        }
    }

    func exportCompleted() {
        if let exportURL {
            TranscriptExporter.removeExport(at: exportURL)
        }
        exportURL = nil
    }

    func discardTranscript() {
        exportCompleted()
        translationTasks.values.forEach { $0.cancel() }
        translationTasks.removeAll()
        speechQueue.stop()
        entries.removeAll()
        partialText = ""
        cancelLivePreview(clearCompletedCache: true)
        learnedTermsNotice = []
    }

    private func preparePreferredRecognizer(
        _ preferred: RecognizerKind,
        revision: Int
    ) async throws -> PreparedRecognizer {
        var lastError: Error = RecognitionServiceError.unavailable
        let candidates = [preferred] + preferred.fallbackCandidates

        for kind in candidates where canAttempt(kind) {
            guard isCurrentLifecycle(revision) else {
                throw CancellationError()
            }
            if kind != preferred {
                statusMessage =
                    "\(preferred.displayName) unavailable. Trying \(kind.displayName)…"
            }
            do {
                return try await prepareRecognizer(kind)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func prepareRecognizer(
        _ kind: RecognizerKind
    ) async throws -> PreparedRecognizer {
        attemptedRecognizers.insert(kind)

        let recognizer: any RecognitionService
        switch kind {
        case .apple:
            recognizer = AppleSpeechRecognitionService(
                vocabulary: vocabularyStore.appleTerms()
            )
        case .sherpaOnDevice:
            recognizer = SherpaOnnxSpeechRecognitionService(
                vocabulary: vocabularyStore.onDeviceTerms()
            )
        case .elevenLabs:
            guard settings.isConfigured, let relayURL = settings.relayURL else {
                throw RecognitionServiceError.missingRelayConfiguration
            }
            recognizer = ElevenLabsSpeechRecognitionService(
                relayURL: relayURL,
                clientToken: settings.clientToken,
                keyterms: vocabularyStore.elevenLabsTerms()
            )
        }

        do {
            try await recognizer.prepare()
            let eventStream = await recognizer.eventStream()
            try await recognizer.start()
            return PreparedRecognizer(
                kind: kind,
                service: recognizer,
                events: eventStream
            )
        } catch {
            await recognizer.stop()
            throw error
        }
    }

    private func install(_ prepared: PreparedRecognizer) {
        let previousEventTask = recognitionEventTask
        activeRecognizer = prepared.service
        activeRecognizerKind = prepared.kind
        recognitionEventTask = Task { @MainActor [weak self] in
            for await event in prepared.events {
                await self?.handleRecognitionEvent(event)
            }
        }
        previousEventTask?.cancel()
    }

    private func handleRecognitionEvent(_ event: RecognitionEvent) async {
        switch event {
        case .ready:
            if phase == .reconnecting {
                phase = .listening
                statusMessage = listeningStatus()
            }
        case .speechStarted:
            break
        case .partial(_, let text):
            handlePartial(text)
        case .speechStopped:
            break
        case .final(let segmentID, let text):
            finalizeUtterance(segmentID: segmentID, text: text)
        case .finished:
            break
        case .error(_, let message, _):
            statusMessage = message
            Task { @MainActor [weak self] in
                await self?.recoverFromRecognizerFailure()
            }
        }
    }

    private func finalizeUtterance(segmentID: String, text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !entries.contains(where: {
                  $0.segmentID == segmentID && $0.sourceText == normalized
              })
        else {
            return
        }

        let cachedPreview: String? = if
            !lastCompletedPreviewTranslation.isEmpty,
            previewPolicy.cacheMatches(
                previewSource: lastCompletedPreviewSource,
                finalSource: normalized
            )
        {
            lastCompletedPreviewTranslation
        } else {
            nil
        }
        cancelLivePreview(clearCompletedCache: true)
        partialText = ""
        partialTranslation = ""

        let priorContext = ContextWindow.build(from: entries)
        let entry = TranscriptEntry(
            segmentID: segmentID,
            sourceText: normalized,
            displayTranslation: cachedPreview,
            spokenTranslation: cachedPreview,
            createdAt: Date(),
            finalizedAt: Date(),
            translationState: .translating,
            speechState: .pending
        )
        entries.append(entry)

        if let cachedPreview {
            if phase.isActive,
               routeState.hasPrivateBluetoothOutput,
               !isMuted {
                speechQueue.enqueue(
                    id: entry.id,
                    text: cachedPreview,
                    createdAt: entry.createdAt
                )
            } else if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index].speechState = routeState.hasPrivateBluetoothOutput
                    ? .muted
                    : .skipped
            }
        }
        requestTranslation(
            for: entry,
            revision: entry.translationRevision,
            context: priorContext,
            allowsAutomaticSpeech: cachedPreview == nil
        )
    }

    private func handlePartial(_ text: String) {
        let normalized = previewPolicy.normalizedSource(text)
        partialText = normalized
        guard !normalized.isEmpty else {
            cancelLivePreview(clearCompletedCache: false)
            partialTranslation = ""
            return
        }
        guard translationClient != nil, previewPolicy.isEligible(normalized) else {
            return
        }

        pendingPreviewText = normalized
        scheduleLivePreviewIfNeeded()
    }

    private func scheduleLivePreviewIfNeeded() {
        guard previewTask == nil,
              !pendingPreviewText.isEmpty,
              phase.isActive
        else {
            return
        }

        previewTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                try Task.checkCancellation()
                await self?.runLivePreview()
            } catch {
                guard let self else { return }
                self.previewTask = nil
                self.isPreviewTranslating = false
            }
        }
    }

    private func runLivePreview() async {
        guard let translationClient,
              !pendingPreviewText.isEmpty,
              phase.isActive
        else {
            previewTask = nil
            isPreviewTranslating = false
            return
        }

        let sourceText = pendingPreviewText
        pendingPreviewText = ""
        guard sourceText != lastCompletedPreviewSource else {
            previewTask = nil
            isPreviewTranslating = false
            scheduleLivePreviewIfNeeded()
            return
        }

        previewSequence += 1
        let sequence = previewSequence
        isPreviewTranslating = true
        let request = TranslationRequest(
            sessionId: sessionID,
            utteranceId: "preview-\(sequence)",
            sourceText: sourceText,
            context: ContextWindow.build(from: entries)
        )

        do {
            let completed = try await translationClient.streamPreview(request) {
                [weak self] visibleText in
                guard let self, self.previewSequence == sequence else { return }
                self.partialTranslation = visibleText
            }
            if !Task.isCancelled, previewSequence == sequence {
                lastCompletedPreviewSource = sourceText
                lastCompletedPreviewTranslation = completed
            }
        } catch is CancellationError {
            // Final recognition or session shutdown superseded the preview.
        } catch {
            // Preview is best-effort. The authoritative final translation still runs.
        }

        previewTask = nil
        isPreviewTranslating = false
        scheduleLivePreviewIfNeeded()
    }

    private func cancelLivePreview(clearCompletedCache: Bool) {
        previewSequence += 1
        previewTask?.cancel()
        previewTask = nil
        pendingPreviewText = ""
        isPreviewTranslating = false
        if clearCompletedCache {
            lastCompletedPreviewSource = ""
            lastCompletedPreviewTranslation = ""
        }
    }

    private func requestTranslation(
        for entry: TranscriptEntry,
        revision: Int,
        context: [TranslationContextTurn],
        allowsAutomaticSpeech: Bool
    ) {
        guard let translationClient else {
            markTranslationUnavailable(id: entry.id, revision: revision)
            return
        }
        let request = TranslationRequest(
            sessionId: sessionID,
            utteranceId: "\(entry.id.uuidString)-r\(revision)",
            sourceText: entry.sourceText,
            context: context
        )

        translationTasks[entry.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await translationClient.translate(request)
                guard !Task.isCancelled,
                      let index = entries.firstIndex(where: { $0.id == entry.id })
                else {
                    return
                }
                let previousSpeechState = entries[index].speechState
                let hadProvisionalSpeech = entries[index].spokenTranslation != nil
                guard
                      entries[index].applyTranslation(
                          display: response.displayTranslation,
                          spoken: response.spokenTranslation,
                          latencyMs: response.latencyMs,
                          revision: revision
                      )
                else {
                    return
                }

                if allowsAutomaticSpeech,
                   phase.isActive,
                   routeState.hasPrivateBluetoothOutput,
                   !isMuted {
                    speechQueue.enqueue(
                        id: entry.id,
                        text: response.spokenTranslation,
                        createdAt: entry.createdAt
                    )
                } else {
                    if hadProvisionalSpeech, !allowsAutomaticSpeech {
                        entries[index].speechState = previousSpeechState
                    } else {
                        entries[index].speechState = allowsAutomaticSpeech ? .muted : .skipped
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                markTranslationUnavailable(id: entry.id, revision: revision)
                if let current = entries.first(where: { $0.id == entry.id }),
                   current.translationRevision == revision {
                    statusMessage = error.localizedDescription
                }
            }

            if let current = entries.first(where: { $0.id == entry.id }),
               current.translationRevision == revision {
                translationTasks[entry.id] = nil
            }
        }
    }

    private func markTranslationUnavailable(id: UUID, revision: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].translationRevision == revision
        else {
            return
        }
        entries[index].translationState = .unavailable
        entries[index].speechState = .muted
    }

    private func recoverFromRecognizerFailure() async {
        guard !fallbackInProgress, phase.isActive else { return }
        fallbackInProgress = true
        let revision = lifecycleRevision
        let failedKind = activeRecognizerKind

        phase = .reconnecting
        let previousRecognizer = activeRecognizer
        var preparedFallback: PreparedRecognizer?
        var lastError: Error = RecognitionServiceError.unavailable

        for candidate in failedKind.fallbackCandidates
            where canAttempt(candidate) {
            statusMessage =
                "\(failedKind.displayName) unavailable. Switching to \(candidate.displayName)…"
            do {
                preparedFallback = try await prepareRecognizer(candidate)
                break
            } catch {
                lastError = error
            }
        }

        guard let preparedFallback else {
            fallbackInProgress = false
            await stopSession(
                finalPhase: .failed(lastError.localizedDescription)
            )
            return
        }

        guard isCurrentLifecycle(revision), phase.isActive else {
            await preparedFallback.service.stop()
            fallbackInProgress = false
            return
        }
        install(preparedFallback)
        if let previousRecognizer {
            await previousRecognizer.stop()
        }
        guard isCurrentLifecycle(revision), phase.isActive else {
            fallbackInProgress = false
            return
        }
        phase = .listening
        statusMessage = listeningStatus()
        fallbackInProgress = false
    }

    private func isCurrentLifecycle(_ revision: Int) -> Bool {
        revision == lifecycleRevision && !Task.isCancelled
    }

    private func canAttempt(_ kind: RecognizerKind) -> Bool {
        guard !attemptedRecognizers.contains(kind) else { return false }
        if kind == .elevenLabs {
            return settings.isConfigured
        }
        return true
    }

    private func listeningStatus() -> String {
        let translationSuffix = translationClient == nil
            ? " Translation is unavailable until the relay is configured."
            : ""
        if routeState.hasPrivateBluetoothOutput {
            return "Listening through the iPhone microphone.\(translationSuffix)"
        }
        return "Captions active. Connect AirPods for private audio.\(translationSuffix)"
    }

    private func handleRouteChange(_ route: AudioRouteState) {
        let hadPrivateOutput = routeState.hasPrivateBluetoothOutput
        routeState = route
        updateSpeechAvailability()

        if hadPrivateOutput, !route.hasPrivateBluetoothOutput {
            statusMessage = "AirPods disconnected. Spoken output is paused; captions continue."
        } else if route.hasPrivateBluetoothOutput {
            statusMessage = "AirPods connected. New translations will be spoken privately."
        }
    }

    private func updateSpeechAvailability() {
        speechQueue.configure(
            enabled: routeState.hasPrivateBluetoothOutput && !isMuted && phase.isActive,
            speechRate: settings.speechRate,
            voiceIdentifier: settings.speechVoiceIdentifier
        )
    }

    private func updateSpeechState(id: UUID, state: SpeechState) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].speechState = state
    }

    private func vocabularyDidChange(_ entries: [VocabularyEntry]) {
        guard let activeRecognizer else { return }
        let learner = VocabularyLearner()
        let terms: [String]
        switch activeRecognizerKind {
        case .apple:
            terms = learner.appleBiasTerms(from: entries)
        case .sherpaOnDevice:
            terms = learner.onDeviceHotwords(from: entries)
        case .elevenLabs:
            terms = learner.elevenLabsKeyterms(from: entries)
        }
        Task {
            await activeRecognizer.updateVocabulary(terms)
        }
    }

    private func pauseForInterruption() async {
        guard phase.isActive else { return }
        await stopSession(finalPhase: .paused)
    }
}
