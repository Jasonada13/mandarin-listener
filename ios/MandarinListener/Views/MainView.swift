import MandarinListenerCore
import SwiftUI

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: SessionController
    @State private var correctionTarget: TranscriptEntry?

    var body: some View {
        NavigationStack {
            ZStack {
                background
                glassContent
            }
            .navigationTitle("Mandarin Listener")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    RoutePickerButton()
                        .frame(width: 36, height: 36)
                        .accessibilityLabel("Choose private audio output")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        controller.isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $controller.isShowingSettings) {
                SettingsView()
                    .environmentObject(settings)
                    .environmentObject(controller.vocabularyStore)
            }
            .sheet(item: $correctionTarget) { entry in
                CaptionCorrectionView(entry: entry) { correctedText in
                    controller.correctCaption(
                        id: entry.id,
                        correctedText: correctedText
                    )
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { controller.exportURL != nil },
                    set: { isPresented in
                        if !isPresented {
                            controller.exportCompleted()
                        }
                    }
                )
            ) {
                if let url = controller.exportURL {
                    ShareSheet(items: [url]) {
                        controller.exportCompleted()
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .sensoryFeedback(.impact, trigger: controller.phase.isActive)
            .overlay(alignment: .bottom) {
                if !controller.learnedTermsNotice.isEmpty {
                    LearnedTermNotice(
                        terms: controller.learnedTermsNotice,
                        onUndo: controller.undoLastVocabularyLearning,
                        onDismiss: controller.dismissLearnedTermsNotice
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: controller.learnedTermsNotice)
            .overlay {
                if scenePhase != .active {
                    ZStack {
                        Color(red: 0.035, green: 0.045, blue: 0.075)
                            .ignoresSafeArea()
                        Label("Mandarin Listener", systemImage: "ear.badge.waveform")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Conversation hidden while the app is inactive")
                }
            }
        }
    }

    @ViewBuilder
    private var glassContent: some View {
#if compiler(>=6.2)
        GlassEffectContainer(spacing: 24) {
            mainContent
        }
#else
        mainContent
#endif
    }

    private var mainContent: some View {
        VStack(spacing: 18) {
            statusPanel
            transcript
            controls
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var background: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.075)
            RadialGradient(
                colors: [
                    Color.cyan.opacity(controller.phase.isActive ? 0.25 : 0.12),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 440
            )
            RadialGradient(
                colors: [Color.indigo.opacity(0.2), Color.clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: controller.phase.isActive)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(controller.phase.label, systemImage: phaseSymbol)
                    .font(.headline)
                    .foregroundStyle(phaseColour)
                Spacer()
                Menu {
                    ForEach(RecognizerKind.allCases) { recognizer in
                        Button {
                            settings.selectedRecognizer = recognizer
                        } label: {
                            if settings.selectedRecognizer == recognizer {
                                Label(recognizer.displayName, systemImage: "checkmark")
                            } else {
                                Text(recognizer.displayName)
                            }
                        }
                    }
                } label: {
                    Label(
                        controller.phase.isActive
                            ? controller.activeRecognizerKind.displayName
                            : settings.selectedRecognizer.displayName,
                        systemImage: "chevron.up.chevron.down"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .disabled(controller.phase.isActive)
                .accessibilityLabel("Default speech recognizer")
                .accessibilityHint("Changes the recognizer used for the next session")
            }

            Text(controller.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                StatusPill(
                    title: "iPhone mic",
                    systemImage: "mic.fill",
                    isActive: controller.phase.isActive
                )
                StatusPill(
                    title: "AirPods",
                    systemImage: "airpods",
                    isActive: controller.routeState.hasPrivateBluetoothOutput
                )
                StatusPill(
                    title: "Network",
                    systemImage: "network",
                    isActive: controller.isNetworkAvailable
                )
                StatusPill(
                    title: controller.isMuted ? "Muted" : "Voice",
                    systemImage: controller.isMuted ? "speaker.slash.fill" : "waveform",
                    isActive: !controller.isMuted
                )
            }
        }
        .padding(18)
        .platformGlassEffect(cornerRadius: 24, tint: phaseColour.opacity(0.08))
        .accessibilityElement(children: .combine)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if controller.entries.isEmpty && controller.partialText.isEmpty {
                        emptyState
                    }

                    ForEach(controller.entries) { entry in
                        TranscriptCard(entry: entry) {
                            correctionTarget = entry
                        }
                            .id(entry.id)
                    }

                    if !controller.partialText.isEmpty {
                        PartialTranscriptCard(
                            text: controller.partialText,
                            translation: controller.partialTranslation,
                            isTranslating: controller.isPreviewTranslating
                        )
                            .id("partial")
                    }
                }
                .padding(.vertical, 4)
            }
            .privacySensitive()
            .scrollIndicators(.hidden)
            .onChange(of: controller.entries.count) {
                withAnimation(.easeOut(duration: 0.25)) {
                    if let lastID = controller.entries.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: controller.partialText) {
                guard !controller.partialText.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("partial", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ready to listen", systemImage: "ear")
        } description: {
            Text("Place the iPhone near the Mandarin speaker, connect AirPods, then start.")
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .foregroundStyle(.secondary)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                controller.isMuted.toggle()
            } label: {
                Image(systemName: controller.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 28, height: 28)
            }
            .platformGlassButton()
            .disabled(!controller.phase.isActive)
            .accessibilityLabel(controller.isMuted ? "Unmute translations" : "Mute translations")

            Button {
                controller.toggleSession()
            } label: {
                Label(
                    primaryButtonTitle,
                    systemImage: controller.phase.isActive ? "stop.fill" : "waveform"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .platformGlassButton(prominent: true)
            .tint(controller.phase.isActive ? .red : .cyan)
            .accessibilityHint(
                controller.phase.isActive
                    ? "Stops microphone capture"
                    : "Starts live Mandarin captions and translation"
            )

            Menu {
                Button {
                    controller.replayLast()
                } label: {
                    Label("Replay last", systemImage: "gobackward")
                }
                .disabled(
                    controller.entries.last?.spokenTranslation == nil
                        || !controller.routeState.hasPrivateBluetoothOutput
                )

                Button {
                    controller.prepareExport()
                } label: {
                    Label("Export transcript", systemImage: "square.and.arrow.up")
                }
                .disabled(controller.entries.isEmpty)

                Button(role: .destructive) {
                    controller.discardTranscript()
                } label: {
                    Label("Discard transcript", systemImage: "trash")
                }
                .disabled(controller.entries.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .platformGlassButton()
            .accessibilityLabel("Session actions")
        }
        .padding(10)
        .platformGlassEffect(cornerRadius: 24)
    }

    private var primaryButtonTitle: String {
        if controller.phase.isActive {
            return "Stop"
        }
        if controller.phase == .paused {
            return "Resume"
        }
        return "Start listening"
    }

    private var phaseSymbol: String {
        switch controller.phase {
        case .idle: "circle"
        case .starting: "hourglass"
        case .listening: "waveform.circle.fill"
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .paused: "pause.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var phaseColour: Color {
        switch controller.phase {
        case .listening: .cyan
        case .starting, .reconnecting: .orange
        case .failed: .red
        case .paused: .yellow
        case .idle: .secondary
        }
    }
}

private struct LearnedTermNotice: View {
    let terms: [String]
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.book.closed.fill")
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(terms.count == 1 ? "Learned term" : "Learned terms")
                    .font(.caption.weight(.semibold))
                Text(terms.joined(separator: "、"))
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .platformGlassEffect(cornerRadius: 18)
    }
}

private extension View {
    @ViewBuilder
    func platformGlassEffect(
        cornerRadius: CGFloat,
        tint: Color = .clear
    ) -> some View {
#if compiler(>=6.2)
        glassEffect(
            .regular.tint(tint),
            in: .rect(cornerRadius: cornerRadius)
        )
#else
        background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint)
                .allowsHitTesting(false)
        }
#endif
    }

    @ViewBuilder
    func platformGlassButton(prominent: Bool = false) -> some View {
#if compiler(>=6.2)
        if prominent {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.glass)
        }
#else
        if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
#endif
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isActive ? Color.primary : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                isActive ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05),
                in: Capsule()
            )
    }
}
