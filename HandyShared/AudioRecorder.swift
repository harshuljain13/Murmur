import AVFoundation
import Foundation

public enum RecordingState {
    case idle
    case recording
    case processing
}

@MainActor
public final class AudioRecorder: ObservableObject {
    @Published public var state: RecordingState = .idle

    private var audioEngine = AVAudioEngine()
    private var recordedSamples: [Float] = []
    private let sampleRate: Double = 16_000

    public init() {}

    public func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recordedSamples.removeAll()
        audioEngine = AVAudioEngine()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecordingError.converterUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
            )
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            converter.convert(to: converted, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let channelData = converted.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(converted.frameLength)))
                Task { @MainActor in self.recordedSamples.append(contentsOf: samples) }
            }
        }

        try audioEngine.start()
        state = .recording
    }

    public func stopRecording() -> [Float] {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false)
        state = .processing
        return recordedSamples
    }
}

public enum RecordingError: Error {
    case converterUnavailable
}
