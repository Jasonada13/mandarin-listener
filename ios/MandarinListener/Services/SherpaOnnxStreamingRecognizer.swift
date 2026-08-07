import Foundation

enum SherpaOnnxRecognizerError: LocalizedError {
    case modelMissing(String)
    case initializationFailed
    case streamCreationFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing(let filename):
            "The on-device Mandarin model is missing \(filename)."
        case .initializationFailed:
            "The on-device Mandarin recognizer could not load."
        case .streamCreationFailed:
            "The on-device Mandarin recognizer could not start a stream."
        }
    }
}

struct SherpaOnnxModelPaths: Sendable {
    let encoder: String
    let decoder: String
    let joiner: String
    let tokens: String
}

final class SherpaOnnxStreamingRecognizer {
    private let recognizer: OpaquePointer
    private var stream: OpaquePointer

    init(paths: SherpaOnnxModelPaths, hotwords: [String]) throws {
        var createdRecognizer: OpaquePointer?

        paths.encoder.withCString { encoder in
            paths.decoder.withCString { decoder in
                paths.joiner.withCString { joiner in
                    paths.tokens.withCString { tokens in
                        "cpu".withCString { provider in
                            "cjkchar".withCString { modelingUnit in
                                "modified_beam_search".withCString { decodingMethod in
                                    var config = SherpaOnnxOnlineRecognizerConfig()
                                    config.feat_config.sample_rate = 16_000
                                    config.feat_config.feature_dim = 80
                                    config.model_config.transducer.encoder = encoder
                                    config.model_config.transducer.decoder = decoder
                                    config.model_config.transducer.joiner = joiner
                                    config.model_config.tokens = tokens
                                    config.model_config.num_threads = 2
                                    config.model_config.provider = provider
                                    // Let sherpa-onnx identify the Zipformer generation
                                    // from ONNX metadata. This model reports zipformer2.
                                    config.model_config.modeling_unit = modelingUnit
                                    config.decoding_method = decodingMethod
                                    config.max_active_paths = 4
                                    config.enable_endpoint = 1
                                    config.rule1_min_trailing_silence = 2.4
                                    config.rule2_min_trailing_silence = 0.8
                                    config.rule3_min_utterance_length = 30
                                    config.hotwords_score = 2
                                    createdRecognizer = SherpaOnnxCreateOnlineRecognizer(
                                        &config
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        guard let createdRecognizer else {
            throw SherpaOnnxRecognizerError.initializationFailed
        }
        recognizer = createdRecognizer

        guard let createdStream = Self.createStream(
            recognizer: createdRecognizer,
            hotwords: hotwords
        ) else {
            SherpaOnnxDestroyOnlineRecognizer(createdRecognizer)
            throw SherpaOnnxRecognizerError.streamCreationFailed
        }
        stream = createdStream
    }

    deinit {
        SherpaOnnxDestroyOnlineStream(stream)
        SherpaOnnxDestroyOnlineRecognizer(recognizer)
    }

    func accept(samples: [Float], sampleRate: Int32 = 16_000) {
        SherpaOnnxOnlineStreamAcceptWaveform(
            stream,
            sampleRate,
            samples,
            Int32(samples.count)
        )
    }

    func decodeAvailableAudio() {
        while SherpaOnnxIsOnlineStreamReady(recognizer, stream) != 0 {
            SherpaOnnxDecodeOnlineStream(recognizer, stream)
        }
    }

    func resultText() -> String {
        guard let result = SherpaOnnxGetOnlineStreamResult(recognizer, stream) else {
            return ""
        }
        defer { SherpaOnnxDestroyOnlineRecognizerResult(result) }
        guard let text = result.pointee.text else { return "" }
        return String(cString: text)
    }

    func isEndpoint() -> Bool {
        SherpaOnnxOnlineStreamIsEndpoint(recognizer, stream) != 0
    }

    func finishInput() {
        SherpaOnnxOnlineStreamInputFinished(stream)
        decodeAvailableAudio()
    }

    func reset(hotwords: [String]) throws {
        guard let replacement = Self.createStream(
            recognizer: recognizer,
            hotwords: hotwords
        ) else {
            throw SherpaOnnxRecognizerError.streamCreationFailed
        }
        let previous = stream
        stream = replacement
        SherpaOnnxDestroyOnlineStream(previous)
    }

    private static func createStream(
        recognizer: OpaquePointer,
        hotwords: [String]
    ) -> OpaquePointer? {
        let normalized = hotwords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard !normalized.isEmpty else {
            return SherpaOnnxCreateOnlineStream(recognizer)
        }
        return normalized.withCString {
            SherpaOnnxCreateOnlineStreamWithHotwords(recognizer, $0)
        }
    }
}
