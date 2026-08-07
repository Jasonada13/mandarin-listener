import Combine
import Foundation
import MandarinListenerCore

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let relayURL = "relayURL"
        static let recognizer = "recognizer"
        static let speechRate = "speechRate"
        static let speechVoiceIdentifier = "speechVoiceIdentifier"
        static let clientToken = "relayClientToken"
    }

    @Published var relayURLText: String {
        didSet { defaults.set(relayURLText, forKey: Key.relayURL) }
    }

    @Published var selectedRecognizer: RecognizerKind {
        didSet { defaults.set(selectedRecognizer.rawValue, forKey: Key.recognizer) }
    }

    @Published var speechRate: Float {
        didSet { defaults.set(speechRate, forKey: Key.speechRate) }
    }

    @Published var speechVoiceIdentifier: String {
        didSet { defaults.set(speechVoiceIdentifier, forKey: Key.speechVoiceIdentifier) }
    }

    @Published private(set) var clientToken: String

    private let defaults: UserDefaults
    private let keychain = KeychainStore(service: "com.jasonadams.MandarinListener")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        relayURLText = defaults.string(forKey: Key.relayURL) ?? ""
        selectedRecognizer = RecognizerKind(
            rawValue: defaults.string(forKey: Key.recognizer) ?? ""
        ) ?? .apple

        let storedRate = defaults.float(forKey: Key.speechRate)
        speechRate = storedRate == 0 ? 0.55 : storedRate
        speechVoiceIdentifier = defaults.string(forKey: Key.speechVoiceIdentifier) ?? ""
        clientToken = KeychainStore(
            service: "com.jasonadams.MandarinListener"
        ).value(for: Key.clientToken) ?? ""
    }

    var relayURL: URL? {
        guard let url = URL(string: relayURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https"
        else {
            return nil
        }
        return url
    }

    var isConfigured: Bool {
        relayURL != nil && clientToken.count >= 32
    }

    func updateClientToken(_ token: String) throws {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try keychain.set(normalized, for: Key.clientToken)
        clientToken = normalized
    }
}
