import Foundation
import AVFoundation

/// Background dictation service.
///
/// PROVEN by on-device testing: (1) the app CAN be kept alive in the background
/// via audio, and (2) iOS refuses to let a backgrounded app START a fresh mic
/// recording ("begin capture error"). Therefore the mic must already be running
/// when the keyboard signals. We keep ONE AVAudioEngine running with the input
/// tapped for the whole time Handy is alive (mic indicator stays on — same as
/// Wispr Flow), and only ACCUMULATE audio while actually dictating.
///
/// Design notes that matter:
/// - Tap installed exactly once (never per-capture) → nothing triggers an
///   AVAudioEngineConfigurationChange mid-dictation.
/// - Correct tap format: inputNode.outputFormat(forBus: 0).
/// - Idle tap buffers are dropped cheaply before any conversion.
final class BackgroundVoiceService: NSObject, @unchecked Sendable {
    static let shared = BackgroundVoiceService()

    private let queue = DispatchQueue(label: "computer.handy.voice")
    private let lock = NSLock()

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?

    // Guarded by `lock`.
    private var captured: [Float] = []
    private var isCapturing = false
    private var heardSpeech = false
    private var silentFrames = 0

    private var observing = false
    private var running = false
    private weak var transcribeService: TranscribeService?

    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    private let maxSamples = 16_000 * 30
    private let silenceStopFrames = 44_000     // ~2.75s of trailing silence
    private let speechThreshold: Float = 0.04  // more forgiving of quiet speech

    private override init() { super.init() }

    // MARK: - Service

    func startService(transcribeService: TranscribeService) {
        self.transcribeService = transcribeService
        queue.async { [weak self] in
            guard let self else { return }
            if !self.observing {
                self.observing = true
                NotificationCenter.default.addObserver(self, selector: #selector(self.onInterruption(_:)),
                                                       name: AVAudioSession.interruptionNotification, object: nil)
                NotificationCenter.default.addObserver(self, selector: #selector(self.onMediaReset(_:)),
                                                       name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
                DarwinSignal.shared.observe(DarwinSignal.recordStart) { [weak self] in
                    VoiceDiagnostics.shared.set(status: "signal recordStart received")
                    self?.queue.async { self?.beginCapture() }
                }
                DarwinSignal.shared.observe(DarwinSignal.recordStop) { [weak self] in
                    self?.queue.async { self?.finish(transcribe: true) }
                }
            }
            self.startEngine()
        }
    }

    /// In-app self-test (foreground). Same path as the keyboard trigger.
    func testCapture() {
        VoiceDiagnostics.shared.set(status: "test: starting…")
        queue.async { [weak self] in self?.beginCapture() }
    }

    // MARK: - Persistent mic engine

    private func startEngine() {
        guard !running else { return }
        let perm = AVAudioApplication.shared.recordPermission
        guard perm == .granted else {
            VoiceDiagnostics.shared.set(status: "need mic permission", keepAlive: false,
                                        error: "Microphone permission not granted")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let fmt = input.outputFormat(forBus: 0)
            guard fmt.sampleRate > 0, fmt.channelCount > 0,
                  let conv = AVAudioConverter(from: fmt, to: targetFormat) else {
                throw NSError(domain: "handy.voice", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "bad input format \(fmt.sampleRate)Hz"])
            }
            converter = conv
            input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buffer, _ in
                self?.consume(buffer, inFormat: fmt)
            }
            engine.prepare()
            try engine.start()
            self.engine = engine
            running = true
            VoiceDiagnostics.shared.set(status: "ready (mic warm)", keepAlive: true, error: "")
        } catch {
            running = false
            teardownEngine()
            VoiceDiagnostics.shared.set(status: "engine failed", keepAlive: false,
                                        error: "startEngine: \(error.localizedDescription)")
        }
    }

    private func teardownEngine() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
        converter = nil
        running = false
    }

    // MARK: - Capture (engine already running → works in background)

    private func beginCapture() {
        if !running { startEngine() }
        guard running else {
            VoiceDiagnostics.shared.set(status: "engine not running")
            return
        }
        lock.lock()
        if isCapturing { lock.unlock(); return }
        captured.removeAll(keepingCapacity: true)
        heardSpeech = false; silentFrames = 0; isCapturing = true
        lock.unlock()

        DarwinSignal.shared.post(DarwinSignal.recordAck)
        VoiceDiagnostics.shared.set(status: "recording…", error: "")
    }

    private func finish(transcribe: Bool) {
        lock.lock()
        guard isCapturing else { lock.unlock(); return }
        isCapturing = false
        let samples = captured
        captured.removeAll(keepingCapacity: false)
        lock.unlock()
        // Engine keeps running (mic warm) — never stopped here.

        let peak = samples.map { abs($0) }.max() ?? 0
        guard transcribe, samples.count > 1_600 else {
            VoiceDiagnostics.shared.set(status: "ready (mic warm)")
            return
        }
        VoiceDiagnostics.shared.set(status: String(format: "transcribing %d smp peak %.3f", samples.count, peak))
        let svc = transcribeService
        Task { @MainActor in
            let text = await svc?.transcribeSamples(samples) ?? nil
            VoiceDiagnostics.shared.status = "ready (mic warm)"
            VoiceDiagnostics.shared.lastTranscript = (text?.isEmpty == false)
                ? text! : String(format: "(empty — %d smp, peak %.3f)", samples.count, peak)
            DarwinSignal.shared.post(DarwinSignal.resultReady)
        }
    }

    // MARK: - Tap (render thread)

    private func consume(_ buffer: AVAudioPCMBuffer, inFormat: AVAudioFormat) {
        lock.lock(); let capturing = isCapturing; lock.unlock()
        guard capturing, let converter else { return }

        let ratio = targetFormat.sampleRate / inFormat.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard cap > 0, let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return }

        var err: NSError?
        var supplied = false
        let status = converter.convert(to: out, error: &err) { _, s in
            if supplied { s.pointee = .noDataNow; return nil }
            supplied = true; s.pointee = .haveData; return buffer
        }
        guard status != .error, err == nil, let ch = out.floatChannelData?[0] else { return }
        let frames = Int(out.frameLength)
        guard frames > 0 else { return }

        var peak: Float = 0
        for i in 0..<frames { peak = max(peak, abs(ch[i])) }

        var shouldStop = false
        lock.lock()
        if isCapturing {
            captured.append(contentsOf: UnsafeBufferPointer(start: ch, count: frames))
            if peak > speechThreshold { heardSpeech = true; silentFrames = 0 }
            else if heardSpeech { silentFrames += frames }
            if (heardSpeech && silentFrames > silenceStopFrames) || captured.count >= maxSamples {
                shouldStop = true
            }
        }
        lock.unlock()

        if shouldStop { queue.async { [weak self] in self?.finish(transcribe: true) } }
    }

    // MARK: - Events (minimal; rebuild only on real disruptions)

    @objc private func onInterruption(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            if type == .began {
                self.lock.lock(); let c = self.isCapturing; self.lock.unlock()
                if c { self.finish(transcribe: true) }
                self.teardownEngine()
            } else {
                self.startEngine()
            }
        }
    }

    @objc private func onMediaReset(_ n: Notification) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.isCapturing = false; self.lock.unlock()
            self.teardownEngine()
            self.startEngine()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
