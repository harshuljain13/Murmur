import UIKit
import AVFoundation

final class KeyboardViewController: UIInputViewController {

    // MARK: - UI
    private let globeButton   = UIButton(type: .system)
    private let micButton     = UIButton(type: .system)
    private let statusLabel   = UILabel()
    private let waveformView  = WaveformView()
    private let downloadButton = UIButton(type: .system)
    private let progressBar   = UIProgressView(progressViewStyle: .default)

    // MARK: - State
    private let store = KeyboardModelStore()
    private var engine: TranscribeEngine?
    private let inferenceQueue = DispatchQueue(label: "computer.handy.inference", qos: .userInitiated)

    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var isRecording = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        refreshState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isRecording { finishRecording(submit: false) }
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)

        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = UIColor.white.withAlphaComponent(0.5)
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globeButton.translatesAutoresizingMaskIntoConstraints = false

        micButton.setImage(micImage("mic.fill"), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        micButton.layer.cornerRadius = 34
        micButton.clipsToBounds = true
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)

        waveformView.barColor = .white
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        waveformView.isHidden = true

        statusLabel.text = "Tap to speak"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        var cfg = UIButton.Configuration.filled()
        cfg.title = "Download Parakeet (477 MB)"
        cfg.baseBackgroundColor = .white
        cfg.baseForegroundColor = .black
        cfg.cornerStyle = .capsule
        downloadButton.configuration = cfg
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        downloadButton.isHidden = true

        progressBar.progressTintColor = .white
        progressBar.trackTintColor = UIColor.white.withAlphaComponent(0.15)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true

        [globeButton, micButton, waveformView, statusLabel, downloadButton, progressBar].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 220),

            globeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            globeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),

            waveformView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            waveformView.topAnchor.constraint(equalTo: view.topAnchor, constant: 44),
            waveformView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            waveformView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            waveformView.heightAnchor.constraint(equalToConstant: 56),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -56),
            micButton.widthAnchor.constraint(equalToConstant: 68),
            micButton.heightAnchor.constraint(equalToConstant: 68),

            statusLabel.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            downloadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            downloadButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            progressBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressBar.topAnchor.constraint(equalTo: downloadButton.bottomAnchor, constant: 16),
            progressBar.widthAnchor.constraint(equalToConstant: 220),
        ])
    }

    private func micImage(_ name: String) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 26))
    }

    // MARK: - State machine

    private func refreshState() {
        if store.isDownloaded {
            downloadButton.isHidden = true
            progressBar.isHidden = true
            micButton.isHidden = false
            setStatus("Tap to speak")
        } else {
            micButton.isHidden = true
            waveformView.isHidden = true
            downloadButton.isHidden = false
            setStatus("Download the model once to enable dictation")
        }
    }

    // MARK: - Model download

    @objc private func downloadTapped() {
        downloadButton.isEnabled = false
        downloadButton.isHidden = true
        progressBar.isHidden = false
        progressBar.progress = 0
        setStatus("Downloading… 0%")

        Task { @MainActor in
            do {
                try await store.download { p in
                    DispatchQueue.main.async { [weak self] in
                        self?.progressBar.progress = Float(p)
                        self?.setStatus("Downloading… \(Int(p * 100))%")
                    }
                }
                self.progressBar.isHidden = true
                self.refreshState()
            } catch {
                self.setStatus("Download failed — tap to retry", error: true)
                self.downloadButton.isEnabled = true
                self.downloadButton.isHidden = false
                self.progressBar.isHidden = true
            }
        }
    }

    // MARK: - Recording

    @objc private func micTapped() {
        guard store.isDownloaded else { return }
        if isRecording { finishRecording(submit: true) }
        else { beginRecording() }
    }

    private var peakDB: Float = -160

    private func beginRecording() {
        // DIAGNOSTIC: surface mic permission state directly in the keyboard.
        let perm = AVAudioApplication.shared.recordPermission
        let permStr: String
        switch perm {
        case .granted:      permStr = "granted"
        case .denied:       permStr = "DENIED"
        case .undetermined: permStr = "UNDETERMINED"
        @unknown default:   permStr = "unknown"
        }
        if perm != .granted {
            setStatus("Mic permission \(permStr) — open Handy app to allow", error: true)
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("handy_rec.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            let started = rec.record()
            guard started else {
                setStatus("record() returned false — mic blocked", error: true)
                return
            }
            audioRecorder = rec
            isRecording = true
            peakDB = -160

            micButton.backgroundColor = UIColor.systemRed
            micButton.setImage(micImage("stop.fill"), for: .normal)
            waveformView.isHidden = false
            waveformView.reset()
            setStatus("Listening…")

            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.sampleMeter()
            }
        } catch {
            setStatus("Mic error: \(error.localizedDescription)", error: true)
        }
    }

    private func sampleMeter() {
        guard let rec = audioRecorder else { return }
        rec.updateMeters()
        let power = rec.averagePower(forChannel: 0) // -160 (silence) ... 0 (loud)
        peakDB = max(peakDB, power)
        let normalized = pow(10, power / 40)        // -160 → ~0.0001, 0 → 1
        waveformView.push(CGFloat(min(1, max(0.02, normalized))))
        // DIAGNOSTIC: show live peak so the user can SEE if signal is captured.
        setStatus(String(format: "Listening…  peak %.0f dB", peakDB))
    }

    private func finishRecording(submit: Bool) {
        meterTimer?.invalidate(); meterTimer = nil
        audioRecorder?.stop()
        let url = audioRecorder?.url
        audioRecorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)

        micButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        micButton.setImage(micImage("mic.fill"), for: .normal)
        waveformView.isHidden = true
        waveformView.reset()

        guard submit, let url else { setStatus("Tap to speak"); return }
        transcribe(url: url)
    }

    // MARK: - Inference (in-process)

    private func transcribe(url: URL) {
        // DIAGNOSTIC: inspect the captured audio before inference.
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let probe = (try? Self.loadPCM(from: url)) ?? []
        let peakAmp = probe.map { abs($0) }.max() ?? 0
        setStatus(String(format: "Got %d samples, peak %.3f — transcribing…", probe.count, peakAmp))

        if probe.isEmpty || peakAmp < 0.001 {
            setStatus(String(format: "Silent audio (%d samples, peak %.4f). Mic not capturing.", probe.count, peakAmp), error: true)
            micButton.isEnabled = true
            return
        }
        _ = fileSize

        micButton.isEnabled = false

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            do {
                if self.engine == nil {
                    self.engine = try TranscribeEngine(modelPath: self.store.modelURL.path)
                }
                let samples = try Self.loadPCM(from: url)
                let text = try self.engine!.transcribe(samples: samples)
                DispatchQueue.main.async {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self.textDocumentProxy.insertText(trimmed)
                        self.setStatus("Tap to speak")
                    } else {
                        // Empty result almost always means silent audio →
                        // mic permission not granted to the Handy app.
                        self.setStatus("No audio — enable mic in the Handy app", error: true)
                    }
                    self.micButton.isEnabled = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.setStatus("Transcription failed", error: true)
                    self.micButton.isEnabled = true
                }
            }
        }
    }

    private static func loadPCM(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        guard let ch = buf.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
    }

    // MARK: - Helpers

    private func setStatus(_ text: String, error: Bool = false) {
        statusLabel.text = text
        statusLabel.textColor = error
            ? UIColor.systemOrange.withAlphaComponent(0.9)
            : UIColor.white.withAlphaComponent(0.45)
    }
}
