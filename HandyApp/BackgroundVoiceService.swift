import Foundation
import AVFoundation

/// Keeps the app alive in the background with a SILENT audio stream so the
/// keyboard's mic button responds instantly (no app relaunch), while the
/// MICROPHONE is only turned on during an actual dictation.
///
/// - Keep-alive: an AVAudioEngine plays a looping silent buffer (background
///   audio) so iOS never suspends the app. No mic involved → no recording
///   indicator when idle.
/// - Dictation: on the keyboard's start signal we install an input tap (mic ON,
///   indicator shows); on stop / pause / 30s cap / interruption / route change
///   we remove the tap (mic OFF) and transcribe. The keep-alive keeps running.
/// - Every audio failure is caught and the engine is rebuilt; the service never
///   crashes the app.
final class BackgroundVoiceService: NSObject, @unchecked Sendable {
    static let shared = BackgroundVoiceService()

    private let queue = DispatchQueue(label: "computer.handy.voice")
    private let lock = NSLock()

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var converter: AVAudioConverter?

    // Guarded by `lock` (audio render thread + control queue).
    private var captured: [Float] = []
    private var isCapturing = false
    private var heardSpeech = false
    private var silentFrames = 0

    private var observing = false
    private var keepAliveRunning = false
    private weak var transcribeService: TranscribeService?

    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    private let maxSamples = 16_000 * 30       // 30s hard cap
    private let silenceStopFrames = 22_000     // ~1.4s trailing silence
    private let speechThreshold: Float = 0.06

    private override init() { super.init() }

    // MARK: - Service lifecycle

    func startService(transcribeService: TranscribeService) {
        self.transcribeService = transcribeService
        queue.async { [weak self] in
            guard let self else { return }
            if !self.observing {
                self.observing = true
                self.registerAudioNotifications()
                DarwinSignal.shared.observe(DarwinSignal.recordStart) { [weak self] in
                    self?.queue.async { self?.beginCapture() }
                }
                DarwinSignal.shared.observe(DarwinSignal.recordStop) { [weak self] in
                    self?.queue.async { self?.finish(transcribe: true) }
                }
            }
            self.startKeepAlive()
        }
    }

    // MARK: - Keep-alive (silent playback; on `queue`)

    private func startKeepAlive() {
        guard !keepAliveRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
            guard fmt.sampleRate > 0,
                  let silent = AVAudioPCMBuffer(pcmFormat: fmt,
                                                frameCapacity: AVAudioFrameCount(fmt.sampleRate * 0.5)) else {
                throw NSError(domain: "handy.voice", code: -10)
            }
            silent.frameLength = silent.frameCapacity   // zero-filled = silence
            engine.connect(player, to: engine.mainMixerNode, format: fmt)
            engine.prepare()
            try engine.start()
            player.scheduleBuffer(silent, at: nil, options: [.loops], completionHandler: nil)
            player.play()

            self.engine = engine
            self.player = player
            self.keepAliveRunning = true
        } catch {
            keepAliveRunning = false
            teardownEngine()
        }
    }

    private func restartKeepAlive() {
        finish(transcribe: false)   // abort any in-flight capture safely
        teardownEngine()
        startKeepAlive()
    }

    private func teardownEngine() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        player = nil
        engine = nil
        converter = nil
        keepAliveRunning = false
    }

    // MARK: - Capture (mic on-demand; on `queue`)

    private func beginCapture() {
        if !keepAliveRunning { startKeepAlive() }
        guard keepAliveRunning, let engine else { return } // no ack → keyboard falls back

        lock.lock(); let already = isCapturing; lock.unlock()
        guard !already else { return }

        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let conv = AVAudioConverter(from: inFormat, to: targetFormat) else {
            return
        }
        converter = conv

        lock.lock()
        captured.removeAll(keepingCapacity: true)
        heardSpeech = false; silentFrames = 0; isCapturing = true
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.consume(buffer, inFormat: inFormat)
        }
        DarwinSignal.shared.post(DarwinSignal.recordAck)
    }

    private func finish(transcribe: Bool) {
        lock.lock()
        guard isCapturing else { lock.unlock(); return }
        isCapturing = false
        let samples = captured
        captured.removeAll(keepingCapacity: false)
        lock.unlock()

        engine?.inputNode.removeTap(onBus: 0)   // mic OFF; keep-alive keeps running
        converter = nil

        guard transcribe, samples.count > 1_600 else { return }
        let svc = transcribeService
        Task { @MainActor in
            _ = await svc?.transcribeSamples(samples)
            DarwinSignal.shared.post(DarwinSignal.resultReady)
        }
    }

    // MARK: - Audio tap (render thread — fast, never crashes)

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

    // MARK: - Audio session / engine events (defensive)

    private func registerAudioNotifications() {
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
        guard let info = n.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                self.finish(transcribe: true)   // stop mic; iOS is taking audio
            case .ended:
                self.restartKeepAlive()          // rebuild keep-alive after the call/Siri
            @unknown default:
                self.restartKeepAlive()
            }
        }
    }

    @objc private func onRouteChange(_ n: Notification) {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let capturing = self.isCapturing; self.lock.unlock()
            if capturing { self.finish(transcribe: true) }  // format changed → finalize
            self.restartKeepAlive()
        }
    }

    @objc private func onConfigChange(_ n: Notification) {
        queue.async { [weak self] in self?.restartKeepAlive() }
    }

    @objc private func onMediaReset(_ n: Notification) {
        queue.async { [weak self] in self?.restartKeepAlive() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
