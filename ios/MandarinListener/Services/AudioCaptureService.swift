@preconcurrency import AVFoundation
import Foundation

final class AudioFrame: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let pcm16: Data

    init(buffer: AVAudioPCMBuffer, pcm16: Data) {
        self.buffer = buffer
        self.pcm16 = pcm16
    }
}

struct AudioRouteState: Equatable, Sendable {
    let inputName: String
    let outputName: String
    let hasPrivateBluetoothOutput: Bool

    static let unknown = AudioRouteState(
        inputName: "Unknown microphone",
        outputName: "No private output",
        hasPrivateBluetoothOutput: false
    )
}

enum AudioCaptureError: LocalizedError {
    case permissionDenied
    case noBuiltInMicrophone
    case invalidFormat
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Microphone access is required."
        case .noBuiltInMicrophone:
            "The built-in iPhone microphone is unavailable."
        case .invalidFormat:
            "The microphone audio format is unsupported."
        case .conversionFailed:
            "Microphone audio could not be converted."
        }
    }
}

@MainActor
final class AudioCaptureService {
    private final class ConversionContext: @unchecked Sendable {
        let converter: AVAudioConverter
        let targetFormat: AVAudioFormat

        init(converter: AVAudioConverter, targetFormat: AVAudioFormat) {
            self.converter = converter
            self.targetFormat = targetFormat
        }
    }

    private final class OwnerReference: @unchecked Sendable {
        weak var value: AudioCaptureService?

        init(_ value: AudioCaptureService) {
            self.value = value
        }
    }

    var onFrame: (@Sendable (AudioFrame) -> Void)?
    var onRouteChange: ((AudioRouteState) -> Void)?
    var onInterruption: ((Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private let engine = AVAudioEngine()
    private var notificationTokens: [NSObjectProtocol] = []
    private(set) var routeState: AudioRouteState = .unknown

    init() {
        observeAudioSession()
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
    }

    func start() async throws {
        guard await requestPermission() else {
            throw AudioCaptureError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothA2DP]
        )
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        guard let builtInMicrophone = session.availableInputs?.first(where: {
            $0.portType == .builtInMic
        }) else {
            throw AudioCaptureError.noBuiltInMicrophone
        }
        try session.setPreferredInput(builtInMicrophone)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
              ),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw AudioCaptureError.invalidFormat
        }

        let tapHandler = Self.makeTapHandler(
            context: ConversionContext(
                converter: converter,
                targetFormat: targetFormat
            ),
            frameHandler: onFrame,
            owner: OwnerReference(self)
        )
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: inputFormat,
            block: tapHandler
        )

        engine.prepare()
        try engine.start()
        updateRouteState()
    }

    private nonisolated static func makeTapHandler(
        context: ConversionContext,
        frameHandler: (@Sendable (AudioFrame) -> Void)?,
        owner: OwnerReference
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            do {
                let frame = try Self.convert(
                    buffer,
                    using: context.converter,
                    targetFormat: context.targetFormat
                )
                frameHandler?(frame)
            } catch {
                Task { @MainActor in
                    owner.value?.onError?(error)
                }
            }
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private nonisolated static func convert(
        _ source: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) throws -> AudioFrame {
        let ratio = targetFormat.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * ratio) + 32)
        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            throw AudioCaptureError.conversionFailed
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
            if suppliedInput {
                statusPointer.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            statusPointer.pointee = .haveData
            return source
        }

        if let conversionError {
            throw conversionError
        }
        guard status != .error, output.frameLength > 0 else {
            throw AudioCaptureError.conversionFailed
        }

        let audioBuffer = output.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData else {
            throw AudioCaptureError.conversionFailed
        }
        let data = Data(bytes: bytes, count: Int(audioBuffer.mDataByteSize))
        return AudioFrame(buffer: output, pcm16: data)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        let routeToken = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateRouteState() }
        }
        let interruptionToken = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawValue)
            else {
                return
            }
            Task { @MainActor in
                self?.onInterruption?(type == .began)
            }
        }
        notificationTokens = [routeToken, interruptionToken]
    }

    private func updateRouteState() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let input = route.inputs.first?.portName ?? "No microphone"
        let output = route.outputs.first?.portName ?? "No output"
        let privateOutput = route.outputs.contains {
            $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE
        }
        routeState = AudioRouteState(
            inputName: input,
            outputName: output,
            hasPrivateBluetoothOutput: privateOutput
        )
        onRouteChange?(routeState)
    }
}
