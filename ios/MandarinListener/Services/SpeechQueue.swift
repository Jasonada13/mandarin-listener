@preconcurrency import AVFoundation
import Foundation
import MandarinListenerCore

@MainActor
final class SpeechQueue: NSObject, AVSpeechSynthesizerDelegate {
    struct Item {
        let id: UUID
        let text: String
        let createdAt: Date
        let estimatedDuration: TimeInterval
    }

    var onStateChange: ((UUID, SpeechState) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private let policy = SpeechBacklogPolicy(maximumBacklog: 5)
    private var pending: [Item] = []
    private var current: Item?
    private var enabled = false
    private var speechRate: Float = 0.55
    private var voiceIdentifier = SpeechVoiceCatalog.automaticIdentifier
    private var cancelledState: SpeechState = .skipped
    private var newestEnqueuedAt = Date.distantPast

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func configure(enabled: Bool, speechRate: Float, voiceIdentifier: String) {
        self.speechRate = speechRate
        self.voiceIdentifier = voiceIdentifier
        setEnabled(enabled)
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        guard !enabled else {
            startNextIfNeeded()
            return
        }

        pending.forEach { onStateChange?($0.id, .muted) }
        pending.removeAll()
        if current != nil {
            cancelledState = .muted
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func enqueue(id: UUID, text: String, createdAt: Date) {
        guard enabled else {
            onStateChange?(id, .muted)
            return
        }

        let newItem = Item(
            id: id,
            text: text,
            createdAt: createdAt,
            estimatedDuration: policy.estimateDuration(for: text)
        )
        guard newItem.estimatedDuration <= policy.maximumBacklog,
              Date().timeIntervalSince(createdAt) <= policy.maximumBacklog,
              createdAt >= newestEnqueuedAt
        else {
            onStateChange?(id, .skipped)
            return
        }
        newestEnqueuedAt = createdAt
        let decision = policy.decision(
            currentUtteranceAge: current.map { Date().timeIntervalSince($0.createdAt) },
            pendingDurations: pending.map(\.estimatedDuration),
            newDuration: newItem.estimatedDuration
        )

        if decision.dropPending {
            pending.forEach { onStateChange?($0.id, .skipped) }
            pending.removeAll()
        }
        pending.append(newItem)

        if decision.interruptCurrentAtWordBoundary, current != nil {
            cancelledState = .skipped
            synthesizer.stopSpeaking(at: .word)
        } else {
            startNextIfNeeded()
        }
    }

    func replay(id: UUID, text: String) {
        guard enabled,
              current?.id != id,
              !pending.contains(where: { $0.id == id })
        else {
            return
        }
        enqueue(id: id, text: text, createdAt: Date())
    }

    @discardableResult
    func cancel(id: UUID) -> Bool {
        pending.removeAll { item in
            guard item.id == id else { return false }
            onStateChange?(item.id, .skipped)
            return true
        }

        guard current?.id == id else {
            return false
        }
        cancelledState = .skipped
        synthesizer.stopSpeaking(at: .immediate)
        return true
    }

    func stop() {
        pending.forEach { onStateChange?($0.id, .skipped) }
        pending.removeAll()
        if current != nil {
            cancelledState = .skipped
            synthesizer.stopSpeaking(at: .immediate)
        }
        newestEnqueuedAt = .distantPast
    }

    private func startNextIfNeeded() {
        guard enabled, current == nil, !pending.isEmpty else { return }
        let item = pending.removeFirst()
        current = item

        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = SpeechVoiceCatalog.voice(
            preferredIdentifier: voiceIdentifier
        )
        utterance.rate = speechRate
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.05
        onStateChange?(item.id, .speaking)
        synthesizer.speak(utterance)
    }

    private func completedCurrent(as state: SpeechState) {
        guard let current else { return }
        onStateChange?(current.id, state)
        self.current = nil
        startNextIfNeeded()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.completedCurrent(as: .spoken)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let state = self.cancelledState
            self.cancelledState = .skipped
            self.completedCurrent(as: state)
        }
    }
}
