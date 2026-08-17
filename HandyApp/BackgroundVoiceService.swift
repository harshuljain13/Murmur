import Foundation
import AVFoundation

/// Runs in the main app and keeps an audio session alive in the background so
/// the keyboard can trigger recording WITHOUT bringing the app to the
/// foreground (the Wispr Flow pattern). Signalled via Darwin notifications.
@MainActor
final class BackgroundVoiceService: ObservableObject {
    static let shared = BackgroundVoiceService()

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    private var captured: [Float] = []
    private var isCapturing = false
    private var running = false
    private weak var transcribeService: TranscribeService?

    // Silence auto-stop
    private var heardSpeech = false
    private var silentFrames = 0

    private init() {}

    func startService(transcribeService: TranscribeService) {
        self.transcribeService = transcribeService
        guard !running else { return }
        do {
            try configureSession()
            try installTapAndRun()
            DarwinSignal.shared.observe(DarwinSignal.recordStart) { [weak self] in self?.beginCapture() }
            DarwinSignal.shared.observe(DarwinSignal.recordStop)  { [weak self] in self?.endCaptureAndTranscribe() }
            running = true
        } catch {
            running = false
        }
    }

    private func configureSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .measurement,
                          options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try s.setActive(true)
    }

    private func installTapAndRun() throws {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in self.process(buffer, inFormat: inFormat) }
        }
        engine.prepare()
        try engine.start()
    }

    private func process(_ buffer: AVAudioPCMBuffer, inFormat: AVAudioFormat) {
        guard isCapturing, let converter else { return }
        let ratio = targetFormat.sampleRate / inFormat.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return }
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            status.pointee = .haveData; return buffer
        }
        guard let ch = out.floatChannelData?[0] else { return }
        let frames = Int(out.frameLength)
        var peak: Float = 0
        for i in 0..<frames { let v = ch[i]; captured.append(v); peak = max(peak, abs(v)) }

        // Silence detection for auto-stop
        if peak > 0.06 { heardSpeech = true; silentFrames = 0 }
        else if heardSpeech { silentFrames += frames }
        // ~1.4s of silence at 16kHz
        if heardSpeech && silentFrames > 22_000 {
            endCaptureAndTranscribe()
        }
    }

    private func beginCapture() {
        captured.removeAll(keepingCapacity: true)
        heardSpeech = false
        silentFrames = 0
        isCapturing = true
        DarwinSignal.shared.post(DarwinSignal.recordAck) // tell keyboard we're live
    }

    private func endCaptureAndTranscribe() {
        guard isCapturing else { return }
        isCapturing = false
        let samples = captured
        captured.removeAll(keepingCapacity: true)
        guard samples.count > 1600 else { return } // <0.1s → ignore

        Task {
            _ = await transcribeService?.transcribeSamples(samples)
            // Result is on the pasteboard; tell the keyboard it's ready.
            DarwinSignal.shared.post(DarwinSignal.resultReady)
        }
    }
}
