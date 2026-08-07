import MandarinListenerCore
import SwiftUI

struct TranscriptCard: View {
    let entry: TranscriptEntry
    let onCorrect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("中文")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
                Spacer()
                stateLabel
            }

            Text(entry.sourceText)
                .font(.title3)
                .fontWeight(.medium)
                .textSelection(.enabled)

            HStack {
                if entry.originalSourceText != nil {
                    Label("Corrected", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Correct", systemImage: "pencil") {
                    onCorrect()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityHint("Edit this Chinese caption and relearn changed terms")
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            Group {
                if let translation = entry.displayTranslation {
                    Text(translation)
                        .foregroundStyle(.primary)
                } else if entry.translationState == .unavailable {
                    Label("Translation unavailable", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Translating…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.body)
            .textSelection(.enabled)
        }
        .padding(17)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch entry.speechState {
        case .speaking:
            Label("Speaking", systemImage: "speaker.wave.2.fill")
                .foregroundStyle(.cyan)
        case .skipped:
            Label("Caption only", systemImage: "text.bubble")
                .foregroundStyle(.secondary)
        case .muted:
            Label("Muted", systemImage: "speaker.slash")
                .foregroundStyle(.secondary)
        case .spoken:
            Image(systemName: "checkmark")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Spoken")
        case .pending:
            EmptyView()
        }
    }
}

struct PartialTranscriptCard: View {
    let text: String
    let translation: String
    let isTranslating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Listening", systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.cyan)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            if !translation.isEmpty || isTranslating {
                Divider()
                    .overlay(Color.white.opacity(0.08))

                HStack(spacing: 7) {
                    Text("Live English")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.mint)
                    if isTranslating {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                if !translation.isEmpty {
                    Text(translation)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(Color.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.cyan.opacity(0.16), style: StrokeStyle(dash: [5, 5]))
        )
        .accessibilityLabel(
            translation.isEmpty
                ? "Partial Mandarin caption: \(text)"
                : "Partial Mandarin caption: \(text). Live English: \(translation)"
        )
    }
}
