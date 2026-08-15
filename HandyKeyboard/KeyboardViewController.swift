import UIKit
import AVFoundation

final class KeyboardViewController: UIInputViewController {

    private let micButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let nextKeyboardButton = UIButton(type: .system)

    private var audioRecorder: AVAudioRecorder?
    private var isRecording = false
    private var pendingRequestId: UUID?
    private var resultPollTimer: Timer?

    private let appGroup = "group.computer.handy"

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = UIColor.systemGroupedBackground

        nextKeyboardButton.setTitle("🌐", for: .normal)
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false

        micButton.setImage(UIImage(systemName: "mic.circle.fill"), for: .normal)
        micButton.contentVerticalAlignment = .fill
        micButton.contentHorizontalAlignment = .fill
        micButton.tintColor = .label
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.addTarget(self, action: #selector(micButtonTapped), for: .touchUpInside)

        statusLabel.text = "Tap mic to speak"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(nextKeyboardButton)
        view.addSubview(micButton)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            nextKeyboardButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            nextKeyboardButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 56),
            micButton.heightAnchor.constraint(equalToConstant: 56),

            statusLabel.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    // MARK: - Recording

    @objc private func micButtonTapped() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let audioURL = tempAudioURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            micButton.tintColor = .systemRed
            micButton.setImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
            statusLabel.text = "Recording…"
        } catch {
            statusLabel.text = "Mic error: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        micButton.tintColor = .label
        micButton.setImage(UIImage(systemName: "mic.circle.fill"), for: .normal)
        statusLabel.text = "Transcribing…"

        guard let url = audioRecorder?.url else { return }
        submitForTranscription(audioURL: url)
    }

    // MARK: - IPC

    private func submitForTranscription(audioURL: URL) {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            statusLabel.text = "App Group error — enable Full Access"
            return
        }

        let sharedAudioURL = containerURL.appendingPathComponent("pending_audio.wav")
        try? FileManager.default.removeItem(at: sharedAudioURL)
        try? FileManager.default.copyItem(at: audioURL, to: sharedAudioURL)

        let request = TranscriptionRequest(audioFileURL: sharedAudioURL)
        pendingRequestId = request.id

        do {
            try TranscriptionBridge.shared.postRequest(request)
            startPollingForResult(requestId: request.id)
        } catch {
            statusLabel.text = "Failed to send request"
        }
    }

    private func startPollingForResult(requestId: UUID) {
        resultPollTimer?.invalidate()
        resultPollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if let result = TranscriptionBridge.shared.readResult(for: requestId) {
                timer.invalidate()
                DispatchQueue.main.async {
                    self.insertText(result.text)
                    self.statusLabel.text = "Tap mic to speak"
                }
            }
        }
        // Timeout after 30s
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.resultPollTimer?.invalidate()
            if self?.statusLabel.text == "Transcribing…" {
                self?.statusLabel.text = "Timed out — open Handy app"
            }
        }
    }

    private func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    private func tempAudioURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("handy_recording.wav")
    }
}
