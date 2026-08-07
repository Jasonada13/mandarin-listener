import MandarinListenerCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var vocabularyStore: VocabularyStore

    @State private var relayURLText = ""
    @State private var token = ""
    @State private var selectedRecognizer: RecognizerKind = .apple
    @State private var speechRate: Float = 0.55
    @State private var speechVoiceIdentifier = SpeechVoiceCatalog.automaticIdentifier
    @State private var connectionState: ConnectionState = .untested

    private enum ConnectionState: Equatable {
        case untested
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "https://mandarin-listener-relay.workers.dev",
                        text: $relayURLText
                    )
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                    SecureField("Client token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task { await testRelay() }
                    } label: {
                        HStack {
                            Label("Test relay", systemImage: "network")
                            Spacer()
                            connectionIndicator
                        }
                    }
                    .disabled(connectionState == .testing)

                    connectionMessage
                } header: {
                    Text("Private relay")
                } footer: {
                    Text(
                        "Only enter the URL of your own deployed relay: this token and translated text are sent to that host. Kimi and ElevenLabs provider keys remain in Cloudflare."
                    )
                }

                Section("Recognition") {
                    Picker("Default recognizer", selection: $selectedRecognizer) {
                        ForEach(RecognizerKind.allCases) { recognizer in
                            Text(recognizer.displayName).tag(recognizer)
                        }
                    }

                }

                Section {
                    if vocabularyStore.entries.isEmpty {
                        Text("Correct a Chinese caption to learn names and places.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vocabularyStore.entries) { entry in
                            HStack {
                                Text(entry.term)
                                Spacer()
                                Text("×\(entry.frequency)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    vocabularyStore.remove(entry)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Forget \(entry.term)")
                            }
                        }
                    }
                } header: {
                    Text("Learned vocabulary")
                } footer: {
                    Text(
                        "Stored only on this iPhone in a protected, non-backed-up file. Apple and Sherpa use up to 100 terms; ElevenLabs uses the top 50 on its next connection."
                    )
                }

                Section("Spoken English") {
                    Picker("Voice", selection: $speechVoiceIdentifier) {
                        Text(automaticVoiceLabel)
                            .tag(SpeechVoiceCatalog.automaticIdentifier)
                        ForEach(SpeechVoiceCatalog.britishEnglishOptions()) { voice in
                            Text(voice.displayName).tag(voice.identifier)
                        }
                    }

                    HStack {
                        Text("Speech rate")
                        Slider(
                            value: Binding(
                                get: { Double(speechRate) },
                                set: { speechRate = Float($0) }
                            ),
                            in: 0.45...0.65
                        )
                        Text(speechRate.formatted(.number.precision(.fractionLength(2))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text("British English is used. Captions are always retained even when stale audio is skipped.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        "For a less robotic voice, download an Enhanced or Premium English (UK) voice in iPhone Settings → Accessibility → Spoken Content → Voices. Then reopen this screen."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Label("Audio is never written to disk.", systemImage: "waveform.badge.shield")
                    Label("Transcripts stay in memory until export or discard.", systemImage: "lock.iphone")
                    Label("Sherpa recognition runs entirely on this iPhone.", systemImage: "iphone.gen3")
                    Label("ElevenLabs receives audio directly; Kimi receives finalized text.", systemImage: "arrow.up.arrow.down")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            settings.relayURLText = relayURLText
                            settings.selectedRecognizer = selectedRecognizer
                            settings.speechRate = speechRate
                            settings.speechVoiceIdentifier = speechVoiceIdentifier
                            try settings.updateClientToken(token)
                            dismiss()
                        } catch {
                            connectionState = .failed("Could not save token.")
                        }
                    }
                }
            }
            .onAppear {
                relayURLText = settings.relayURLText
                token = settings.clientToken
                selectedRecognizer = settings.selectedRecognizer
                speechRate = settings.speechRate
                speechVoiceIdentifier = settings.speechVoiceIdentifier
            }
        }
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        switch connectionState {
        case .untested:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var connectionMessage: some View {
        switch connectionState {
        case .untested:
            Text("Enter both fields, then test before saving.")
                .foregroundStyle(.secondary)
        case .testing:
            Text("Testing the private relay…")
                .foregroundStyle(.secondary)
        case .success:
            Label("Relay connected and authenticated.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func testRelay() async {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let relayURL = localRelayURL, normalizedToken.count >= 32 else {
            connectionState = .failed("Enter the relay client token too.")
            return
        }
        connectionState = .testing
        do {
            let endpoint = relayURL
                .appending(path: "v1")
                .appending(path: "auth")
                .appending(path: "check")
            var request = URLRequest(url: endpoint)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 5
            request.setValue(
                "Bearer \(normalizedToken)",
                forHTTPHeaderField: "Authorization"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let identity = try? JSONDecoder().decode(
                      RelayIdentity.self,
                      from: data
                  ),
                  identity.status == "ok",
                  identity.service == "mandarin-listener-relay",
                  identity.authenticated
            else {
                throw URLError(.badServerResponse)
            }
            connectionState = .success
        } catch {
            connectionState = .failed(error.localizedDescription)
        }
    }

    private struct RelayIdentity: Decodable {
        let status: String
        let service: String
        let authenticated: Bool
    }

    private var localRelayURL: URL? {
        guard let url = URL(
            string: relayURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        url.scheme?.lowercased() == "https"
        else {
            return nil
        }
        return url
    }

    private var automaticVoiceLabel: String {
        guard let best = SpeechVoiceCatalog.britishEnglishOptions().first else {
            return "Best available"
        }
        return "Best available (\(best.name) · \(best.qualityLabel))"
    }
}
