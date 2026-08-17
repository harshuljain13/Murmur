import Foundation
import AVFoundation

/// Handles the microphone DYNAMICALLY and defensively:
/// - Mic is OFF whenever idle (no engine, no session) — no battery drain, no
///   permanent recording indicator.
/// - The keyboard's voice button (recordStart signal) turns the mic ON.
/// - Stop (recordStop signal), a speech pause, a 30s cap, an interruption, or a
///   route change turns it OFF and transcribes what was captured.
/// - Every AVAudioSession/engine failure is caught; the service never crashes
///   the app — worst case it aborts the capture and lets the keyboard time out.
final class BackgroundVoiceService: NSObject, @unchecked Sendable {
    static let shared = BackgroundVoiceService()

    private let queue = DispatchQueue(label: "computer.handy.voice")
    private let lock = NSLock()

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!

    // Guarded by `lock` (touched from the audio render thread + control queue).
    private var captured: [Float] = []
    private var isCapturing = false
    private var heardSpeech = false
    private var silentFrames = 0

    private var observing = false
    private weak var transcribeService: TranscribeService?

    private let maxSamples = 16_000 * 30       // 30s hard cap
    private let silenceStopFrames = 22_000     // ~1.4s of trailing silence
    private let speechThreshold: Float = 0.06

    private override init() { super.init() }

    // MARK: - Service lifecycle

    /// Registers signal + audio-event observers. Does NOT touch the mic.
    func startService(transcribeService: TranscribeService) {
        self.transcribeService = transcribeService
        queue.async { [weak self] in
            guard let self, !self.observing else { return }
            self.observing = true
            self.registerAudioNotifications()
            DarwinSignal.shared.observe(DarwinSignal.recordStart) { [weak self] in
                self?.queue.async { self?.beginCapture() }
            }
            DarwinSignal.shared.observe(DarwinSignal.recordStop) { [weak self] in
                self?.queue.async { self?.finish(transcribe: true) }
            }
        }
    }

    // MARK: - Capture control (all on `queue`)

    private func beginCapture() {
        lock.lock(); let already = isCapturing; lock.unlock()
        guard !already else { return }

        do {
            try startEngine()
        } catch {
            teardownEngine()          // leave mic fully off; keyboard will time out
            return
        }

        lock.lock()
        captured.removeAll(keepingCapacity: true)
        heardSpeech = false
        silentFrames = 0
        isCapturing = true
        lock.unlock()

        DarwinSignal.shared.post(DarwinSignal.recordAck) // "I'm live"
    }

    /// Stop the mic and optionally transcribe. Safe to call repeatedly.
    private func finish(transcribe: Bool) {
        lock.lock()
        guard isCapturing else { lock.unlock(); return }
        isCapturing = false
        let samples = captured
        captured.removeAll(keepingCapacity: false)
        lock.unlock()

        teardownEngine()               // mic OFF, session released to other apps

        guard transcribe, samples.count > 1_600 else { return }  // ignore < 0.1s
        let svc = transcribeService
        Task { @MainActor in
            _ = await svc?.transcribeSamples(samples)
            DarwinSignal.shared.post(DarwinSignal.resultReady)
        }
    }

    // MARK: - Engine (on `queue`)

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: [])

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)

        // Guard against an invalid/zero hardware format — installing a tap with
        // it would crash. Bail cleanly instead.
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw NSError(domain: "handy.voice", code: -1)
        }
        guard let converter = AVAudioConverter(from: inFormat, to: targetFormat) else {
            throw NSError(domain: "handy.voice", code: -2)
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.consume(buffer, inFormat: inFormat)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func teardownEngine() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
        converter = nil
        // Release the session so other apps regain audio and the mic light goes off.
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Audio tap (real-time thread — must be fast + never crash)

    private func consume(_ buffer: AVAudioPCMBuffer, inFormat: AVAudioFormat) {
        guard let converter else { return }
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

    // MARK: - Audio session events (defensive)

    private func registerAudioNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleMediaReset(_:)),
                       name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    /// Any disruption during capture → stop safely and transcribe what we have,
    /// rather than risk the engine crashing on a changed route/format.
    @objc private func handleInterruption(_ n: Notification) {
        queue.async { [weak self] in self?.finish(transcribe: true) }
    }

    @objc private func handleRouteChange(_ n: Notification) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let capturing = self.isCapturing; self.lock.unlock()
            if capturing { self.finish(transcribe: true) }
        }
    }

    @objc private func handleMediaReset(_ n: Notification) {
        queue.async { [weak self] in self?.finish(transcribe: false) }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
