import UIKit
import AVFoundation

final class KeyboardViewController: UIInputViewController {

    // MARK: - UI
    private let micButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let nextKeyboardButton = UIButton(type: .system)

    // MARK: - State
    private var audioRecorder: AVAudioRecorder?
    private var isRecording = false
    private var pollTimer: Timer?
    private var requestTimestamp: TimeInterval = 0

    private let bridge = TranscriptionBridge.shared

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pollTimer?.invalidate()
        if isRecording { stopRecording(submit: false) }
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1)

        // Globe key
        nextKeyboardButton.setTitle("🌐", for: .normal)
        nextKeyboardButton.titleLabel?.font = .systemFont(ofSize: 20)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false

        // Mic
        micButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        micButton.layer.cornerRadius = 36
        micButton.clipsToBounds = true
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)

        // Status
        statusLabel.text = "Tap mic to speak"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.4)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        [nextKeyboardButton, micButton, statusLabel].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 160),

            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            nextKeyboardButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -8),
            micButton.widthAnchor.constraint(equalToConstant: 72),
            micButton.heightAnchor.constraint(equalToConstant: 72),

            statusLabel.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        // Note: we can't reliably check model state across the process boundary
        // without an App Group, so the mic is always enabled. If no model is
        // downloaded, the main app writes back an error result which we display.
    }

    // MARK: - Recording

    @objc private func micTapped() {
        if isRecording { stopRecording(submit: true) }
        else { startRecording() }
    }

    private func startRecording() {
        let audioURL = bridge.audioDirURL().appendingPathComponent("pending.wav")

        let settings: [String: Any] = [
            AVFormatIDKey:            Int(kAudioFormatLinearPCM),
            AVSampleRateKey:          16_000,
            AVNumberOfChannelsKey:    1,
            AVLinearPCMBitDepthKey:   16,
            AVLinearPCMIsFloatKey:    false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            micButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
            micButton.setImage(UIImage(systemName: "stop.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
            setStatus("Recording…")
        } catch {
            setStatus("Mic error — enable Full Access in Settings", error: true)
        }
    }

    private func stopRecording(submit: Bool) {
        audioRecorder?.stop()
        isRecording = false
        micButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        micButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
        try? AVAudioSession.sharedInstance().setActive(false)

        guard submit, let url = audioRecorder?.url else { setStatus("Tap mic to speak"); return }
        guard let audioData = try? Data(contentsOf: url) else { setStatus("Recording error"); return }

        // UIPasteboard.general is readable by both the extension and the main app
        // without any entitlements. We use a named type so we don't clobber the user's clipboard.
        UIPasteboard.general.setData(audioData, forPasteboardType: "computer.handy.audio")
        submitToApp()
    }

    // MARK: - IPC

    private func submitToApp() {
        setStatus("Transcribing…")
        bridge.clearResult()
        requestTimestamp = Date().timeIntervalSince1970

        // Wake / foreground the main app
        let url = URL(string: "handy://transcribe")!
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url)
                break
            }
            responder = r.next
        }

        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let started = requestTimestamp
        var elapsed = 0.0
        let bridge = self.bridge

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }

            if let result = bridge.readResult(newerThan: started) {
                timer.invalidate()
                DispatchQueue.main.async {
                    if result.hasPrefix("ERROR:") {
                        self.setStatus(String(result.dropFirst(7)), error: true)
                    } else {
                        self.textDocumentProxy.insertText(result)
                        self.setStatus("Tap mic to speak")
                    }
                    bridge.clearResult()
                }
                return
            }

            elapsed += 0.3
            if elapsed >= 30 {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.setStatus("Timed out — is Handy app installed?", error: true)
                }
            }
        }
    }

    // MARK: - Helpers

    private func setStatus(_ text: String, error: Bool = false) {
        statusLabel.text = text
        statusLabel.textColor = error
            ? UIColor.systemOrange.withAlphaComponent(0.9)
            : UIColor.white.withAlphaComponent(0.4)
    }
}
