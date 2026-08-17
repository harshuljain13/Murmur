import Foundation
import AVFoundation

/// Background voice service built on PROVEN high-level APIs:
/// - Keep-alive: an `AVAudioPlayer` loops a silent file so iOS keeps the app
///   alive in the background (no mic → no recording indicator when idle).
/// - Dictation: an `AVAudioRecorder` (the same path that works in the foreground)
///   records 16 kHz mono on the keyboard's signal; the mic light shows only while
///   recording. Silence / 30s cap auto-stops it, then we transcribe.
///
/// No AVAudioEngine → no configuration-change self-destruction, no format traps.
/// Every failure is caught and reported to `VoiceDiagnostics`; never crashes.
final class BackgroundVoiceService: NSObject, @unchecked Sendable {
    static let shared = BackgroundVoiceService()

    private let queue = DispatchQueue(label: "computer.handy.voice")

    private var keepAlivePlayer: AVAudioPlayer?
    private var recorder: AVAudioRecorder?
    private var meterTimer: DispatchSourceTimer?

    private var observing = false
    private var isRecording = false
    private var heardSpeech = false
    private var silentTicks = 0
    private var totalTicks = 0

    private weak var transcribeService: TranscribeService?

    private let recURL = FileManager.default.temporaryDirectory.appendingPathComponent("handy_bg_rec.wav")
    private let speechLevel: CGFloat = 0.14
    private let silenceTicksToStop = 28   // ~1.4s at 0.05s ticks
    private let maxTicks = 600            // 30s hard cap

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
            self.startKeepAlive()
        }
    }

    /// Foreground self-test used by the in-app "Test Microphone" button.
    func testCapture() { queue.async { [weak self] in self?.beginCapture() } }

    // MARK: - Keep-alive (silent playback)

    private func startKeepAlive() {
        do {
            try activateSession()
            if keepAlivePlayer == nil {
                guard let url = silentFileURL() else { throw NSError(domain: "handy.voice", code: -20) }
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.volume = 0
                player.prepareToPlay()
                keepAlivePlayer = player
            }
            if keepAlivePlayer?.isPlaying == false { keepAlivePlayer?.play() }
            VoiceDiagnostics.shared.set(status: "ready (idle)", keepAlive: keepAlivePlayer?.isPlaying == true, error: "")
        } catch {
            VoiceDiagnostics.shared.set(status: "keep-alive failed", keepAlive: false,
                                        error: "keepAlive: \(error.localizedDescription)")
        }
    }

    private func activateSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default,
                          options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try s.setActive(true, options: [])
    }

    private func silentFileURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("handy_silence.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else { return nil }
        do {
            let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 44_100) else { return nil }
            buf.frameLength = buf.frameCapacity   // 1s of silence (zeros)
            try file.write(from: buf)
            return url
        } catch { return nil }
    }

    // MARK: - Dictation (AVAudioRecorder)

    private func beginCapture() {
        guard !isRecording else { return }
        do {
            try activateSession()   // ensure session live even if keep-alive lapsed
            try? FileManager.default.removeItem(at: recURL)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let rec = try AVAudioRecorder(url: recURL, settings: settings)
            rec.isMeteringEnabled = true
            guard rec.record() else {
                VoiceDiagnostics.shared.set(status: "record() refused", error: "AVAudioRecorder.record() returned false")
                return   // no ack → keyboard falls back
            }
            recorder = rec
            isRecording = true
            heardSpeech = false; silentTicks = 0; totalTicks = 0
            startMeterTimer()
            DarwinSignal.shared.post(DarwinSignal.recordAck)   // "mic is live"
            VoiceDiagnostics.shared.set(status: "recording…", error: "")
        } catch {
            VoiceDiagnostics.shared.set(status: "record failed", error: "beginCapture: \(error.localizedDescription)")
            cleanupRecorder()
        }
    }

    private func startMeterTimer() {
        meterTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.05, repeating: 0.05)
        t.setEventHandler { [weak self] in self?.sampleMeter() }
        meterTimer = t
        t.resume()
    }

    private func sampleMeter() {
        guard isRecording, let rec = recorder else { return }
        rec.updateMeters()
        let power = rec.averagePower(forChannel: 0)      // -160…0 dB
        let level = CGFloat(pow(10, power / 40))
        totalTicks += 1
        if level > speechLevel { heardSpeech = true; silentTicks = 0 }
        else if heardSpeech { silentTicks += 1 }
        if (heardSpeech && silentTicks >= silenceTicksToStop) || totalTicks >= maxTicks {
            finish(transcribe: true)
        }
    }

    private func finish(transcribe: Bool) {
        guard isRecording else { return }
        isRecording = false
        meterTimer?.cancel(); meterTimer = nil
        recorder?.stop()
        let url = recorder?.url
        recorder = nil                          // mic OFF; keep-alive player continues

        guard transcribe, let url,
              FileManager.default.fileExists(atPath: url.path) else {
            VoiceDiagnostics.shared.set(status: "ready (idle)")
            return
        }
        VoiceDiagnostics.shared.set(status: "transcribing…")
        let svc = transcribeService
        Task { @MainActor in
            let text = await svc?.transcribeSamples(Self.loadPCM(url)) ?? nil
            VoiceDiagnostics.shared.status = "ready (idle)"
            VoiceDiagnostics.shared.lastTranscript = text ?? "(no speech detected)"
            DarwinSignal.shared.post(DarwinSignal.resultReady)
        }
    }

    private func cleanupRecorder() {
        meterTimer?.cancel(); meterTimer = nil
        recorder?.stop(); recorder = nil
        isRecording = false
    }

    private static func loadPCM(_ url: URL) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url),
              let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length)) else { return [] }
        do { try file.read(into: buf) } catch { return [] }
        guard let ch = buf.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
    }

    // MARK: - Audio session events

    private func registerNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onInterruption(_:)),
                       name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(onMediaReset(_:)),
                       name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        // NOTE: route changes are handled inside AVAudioRecorder; no engine to rebuild.
    }

    @objc private func onInterruption(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                if self.isRecording { self.finish(transcribe: true) }
                self.keepAlivePlayer?.pause()
            case .ended:
                self.startKeepAlive()   // reactivate session + resume silent loop
            @unknown default:
                self.startKeepAlive()
            }
        }
    }

    @objc private func onMediaReset(_ n: Notification) {
        queue.async { [weak self] in
            guard let self else { return }
            self.cleanupRecorder()
            self.keepAlivePlayer = nil
            self.startKeepAlive()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
