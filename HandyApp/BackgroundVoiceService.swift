import Foundation
import AVFoundation

/// Background dictation service.
///
/// iOS forbids an app from STARTING microphone capture while backgrounded — it
/// only lets a mic session that's already running continue. So to let the
/// keyboard trigger dictation in the background (no app relaunch), we keep a
/// persistent mic engine running the whole time Handy is alive (mic indicator
/// stays on — same as Wispr Flow). We only *accumulate* audio while actually
/// dictating; the rest of the time the tapped buffers are discarded.
///
/// The tap is installed ONCE (never per-capture), so nothing fires
/// AVAudioEngineConfigurationChange mid-dictation. Correct input format is used.
/// Interruptions / route changes / media resets rebuild the engine safely.
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
    private var running = false          // engine started + tap installed
    private weak var transcribeService: TranscribeService?

    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    private let maxSamples = 16_000 * 30
    private let silenceStopFrames = 22_000
    private let speechThreshold: Float = 0.06

    private override init() { super.init() }

    // MARK: - Service

    func startService(transcribeService: TranscribeService) {
        self.transcribeService = transcribeService
        queue.async { [weak self] in
            guard let self else { return }
            if !self.observing {
                self.observing = true
                self.registerNotifications()
                DarwinSignal.shared.observe(DarwinSignal.recordStart) { [weak self] in
                    self?.queue.async { self?.beginCapture() }
                }
                DarwinSignal.shared.observe(DarwinSignal.recordStop) { [weak self] in
                    self?.queue.async { self?.finish(transcribe: true) }
                }
            }
            self.startEngine()
        }
    }

    /// In-app self-test (foreground). Reuses the same capture path.
    func testCapture() {
        VoiceDiagnostics.shared.set(status: "test: starting…")
        queue.async { [weak self] in self?.beginCapture() }
    }

    // MARK: - Persistent mic engine (on `queue`)

    private func startEngine() {
        guard !running else { return }

        let perm = AVAudioApplication.shared.recordPermission
        guard perm == .granted else {
            VoiceDiagnostics.shared.set(status: "mic permission not granted", keepAlive: false,
                                        error: "Grant microphone access to enable dictation")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let fmt = input.outputFormat(forBus: 0)              // CORRECT tap format
            guard fmt.sampleRate > 0, fmt.channelCount > 0,
                  let conv = AVAudioConverter(from: fmt, to: targetFormat) else {
                throw NSError(domain: "handy.voice", code: -1)
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

    private func restartEngine() {
        lock.lock(); let capturing = isCapturing; lock.unlock()
        if capturing { finish(transcribe: true) }
        teardownEngine()
        startEngine()
    }

    // MARK: - Capture control

    private func beginCapture() {
        if !running { startEngine() }
        guard running else { return }   // no ack → keyboard falls back

        lock.lock()
        guard !isCapturing else { lock.unlock(); return }
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
        // NOTE: engine keeps running (mic stays warm) — do NOT stop it.

        guard transcribe, samples.count > 1_600 else {
            VoiceDiagnostics.shared.set(status: "ready (mic warm)")
            return
        }
        let peak = samples.map { abs($0) }.max() ?? 0
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

    // MARK: - Audio tap (render thread)

    private func consume(_ buffer: AVAudioPCMBuffer, inFormat: AVAudioFormat) {
        // Cheap early-out when idle: the mic is always warm, but we only spend
        // cycles converting/accumulating while actually dictating.
        lock.lock(); let capturing = isCapturing; lock.unlock()
        guard capturing, let converter else { return }

        let ratio = targetFormat.sampleRate / inFormat.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard cap > 0, let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return }

        var err: NSError?
        var supplied = false
        let status = converter.convert(to: out, error: &err) { _, inStatus in
            if supplied { inStatus.pointee = .noDataNow; return nil }
            supplied = true; inStatus.pointee = .haveData; return buffer
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

    // MARK: - Audio session / engine events

    private func registerNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onInterruption(_:)),
                       name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(onRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(onMediaReset(_:)),
                       name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        nc.addObserver(self, selector: #selector(onConfigChange(_:)),
                       name: .AVAudioEngineConfigurationChange, object: nil)
    }

    @objc private func onInterruption(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                self.lock.lock(); let c = self.isCapturing; self.lock.unlock()
                if c { self.finish(transcribe: true) }
                self.teardownEngine()          // iOS took the session
            case .ended:
                self.startEngine()             // bring the mic back
            @unknown default:
                self.restartEngine()
            }
        }
    }

    @objc private func onRouteChange(_ n: Notification) {
        queue.async { [weak self] in self?.restartEngine() }
    }

    @objc private func onConfigChange(_ n: Notification) {
        queue.async { [weak self] in
            guard let self, self.running else { return }   // ignore the install-time change
            self.restartEngine()
        }
    }

    @objc private func onMediaReset(_ n: Notification) {
        queue.async { [weak self] in self?.restartEngine() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
