@preconcurrency import AVFoundation
import Foundation

struct SpeechVoiceOption: Identifiable, Hashable {
    let identifier: String
    let name: String
    let quality: AVSpeechSynthesisVoiceQuality

    var id: String { identifier }

    var qualityLabel: String {
        switch quality {
        case .premium:
            "Premium"
        case .enhanced:
            "Enhanced"
        default:
            "Compact"
        }
    }

    var displayName: String {
        "\(name) · \(qualityLabel)"
    }
}

@MainActor
enum SpeechVoiceCatalog {
    static let automaticIdentifier = ""

    static func britishEnglishOptions() -> [SpeechVoiceOption] {
        britishEnglishVoices().map {
            SpeechVoiceOption(
                identifier: $0.identifier,
                name: $0.name,
                quality: $0.quality
            )
        }
    }

    static func voice(preferredIdentifier: String) -> AVSpeechSynthesisVoice? {
        if !preferredIdentifier.isEmpty,
           let preferred = AVSpeechSynthesisVoice(identifier: preferredIdentifier),
           isBritishEnglish(preferred),
           !preferred.voiceTraits.contains(.isNoveltyVoice) {
            return preferred
        }
        return britishEnglishVoices().first
            ?? AVSpeechSynthesisVoice(language: "en-GB")
    }

    private static func britishEnglishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter {
                isBritishEnglish($0)
                    && !$0.voiceTraits.contains(.isNoveltyVoice)
            }
            .sorted { left, right in
                if left.quality.rawValue != right.quality.rawValue {
                    return left.quality.rawValue > right.quality.rawValue
                }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
    }

    private static func isBritishEnglish(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.language.caseInsensitiveCompare("en-GB") == .orderedSame
    }
}
