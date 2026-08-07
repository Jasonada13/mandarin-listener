import Foundation
import MandarinListenerCore

protocol RecognitionService: AnyObject, Sendable {
    func eventStream() async -> AsyncStream<RecognitionEvent>
    func prepare() async throws
    func start() async throws
    func ingest(_ frame: AudioFrame) async
    func updateVocabulary(_ terms: [String]) async
    func stop() async
}

enum RecognitionServiceError: LocalizedError {
    case unsupportedLocale
    case speechPermissionDenied
    case unavailable
    case missingRelayConfiguration

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale:
            "Mandarin speech recognition is not supported on this device."
        case .speechPermissionDenied:
            "Speech recognition permission is required for the Apple recognizer."
        case .unavailable:
            "Speech recognition is currently unavailable."
        case .missingRelayConfiguration:
            "Add the relay URL and client token in Settings."
        }
    }
}
