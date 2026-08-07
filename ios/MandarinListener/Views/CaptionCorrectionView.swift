import MandarinListenerCore
import SwiftUI

struct CaptionCorrectionView: View {
    @Environment(\.dismiss) private var dismiss

    let entry: TranscriptEntry
    let onSave: (String) -> Void

    @State private var correctedText: String

    init(entry: TranscriptEntry, onSave: @escaping (String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _correctedText = State(initialValue: entry.sourceText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $correctedText)
                        .font(.title3)
                        .frame(minHeight: 140)
                        .autocorrectionDisabled()
                } header: {
                    Text("Chinese caption")
                } footer: {
                    Text(
                        "Saving retranslates this caption. Only changed Chinese terms are learned as recognition bias; future captions are never rewritten automatically."
                    )
                }

                if let original = entry.originalSourceText {
                    Section {
                        Text(original)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } header: {
                        Text("First recognised as")
                    }
                }
            }
            .navigationTitle("Correct caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(correctedText)
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isSaveDisabled: Bool {
        let normalized = correctedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized.isEmpty || normalized == entry.sourceText
    }
}
