import UIKit

/// Full-size Handy dictation panel (same height as a keyboard). Idle: a light
/// background with a big mic button. Tap it and the whole panel becomes an
/// animated waveform with ✕ cancel and ✓ confirm — the panel never resizes.
/// Recording + CPU transcription run in the Handy app in the background; the
/// transcript is inserted in place.
final class KeyboardViewController: UIInputViewController {

    private let bg    = UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1)   // soft light
    private let ink   = UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    private let pink  = UIColor.handyPinkDeep

    // Idle
    private let micButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    // Listening / transcribing
    private let cancelButton  = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)
    private let waveform      = WaveBars()
    private let statusLabel   = UILabel()

    // IPC
    private let bridge = TranscriptionBridge.shared
    private let signal = DarwinSignal.shared
    private let lastInsertedKey = "handy.lastInsertedTS"
    private enum Mode { case idle, listening, transcribing }
    private var mode: Mode = .idle
    private var requestTime: TimeInterval = 0
    private var gotAck = false
    private var pollTimer: Timer?, ackTimer: Timer?, watchdog: Timer?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bg
        buildUI()
        signal.observe(DarwinSignal.recordAck)   { [weak self] in self?.onAck() }
        signal.observe(DarwinSignal.resultReady) { [weak self] in self?.tryInsertResult() }
        setMode(.idle)
        tryInsertResult()
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tryInsertResult() }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if mode == .listening { signal.post(DarwinSignal.recordCancel) }
        cancelTimers()
    }

    // MARK: - UI

    private func buildUI() {
        // Big mic button (idle)
        var micCfg = UIButton.Configuration.filled()
        micCfg.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold))
        micCfg.baseBackgroundColor = pink
        micCfg.baseForegroundColor = .white
        micCfg.cornerStyle = .capsule
        micButton.configuration = micCfg
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.addTarget(self, action: #selector(startListening), for: .touchUpInside)

        hintLabel.text = "Tap to dictate"
        hintLabel.font = .systemFont(ofSize: 16, weight: .medium)
        hintLabel.textColor = ink.withAlphaComponent(0.5)
        hintLabel.textAlignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        // Cancel ✕
        cancelButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)), for: .normal)
        cancelButton.tintColor = ink.withAlphaComponent(0.7)
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.06)
        cancelButton.layer.cornerRadius = 30
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelListening), for: .touchUpInside)

        // Confirm ✓
        confirmButton.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .bold)), for: .normal)
        confirmButton.tintColor = .white
        confirmButton.backgroundColor = pink
        confirmButton.layer.cornerRadius = 30
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(confirmListening), for: .touchUpInside)

        waveform.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = ink.withAlphaComponent(0.5)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        [micButton, hintLabel, cancelButton, confirmButton, waveform, statusLabel].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 258),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -14),
            micButton.widthAnchor.constraint(equalToConstant: 92),
            micButton.heightAnchor.constraint(equalToConstant: 92),
            hintLabel.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 14),
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            cancelButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -14),
            cancelButton.widthAnchor.constraint(equalToConstant: 60),
            cancelButton.heightAnchor.constraint(equalToConstant: 60),

            confirmButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            confirmButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -14),
            confirmButton.widthAnchor.constraint(equalToConstant: 60),
            confirmButton.heightAnchor.constraint(equalToConstant: 60),

            waveform.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 20),
            waveform.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -20),
            waveform.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            waveform.heightAnchor.constraint(equalToConstant: 40),

            statusLabel.topAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    private func setMode(_ m: Mode) {
        mode = m
        let listening = (m == .listening || m == .transcribing)
        micButton.isHidden = listening
        hintLabel.isHidden = listening && m == .listening
        cancelButton.isHidden = !listening
        confirmButton.isHidden = !listening
        waveform.isHidden = !listening
        statusLabel.isHidden = !listening

        switch m {
        case .idle:
            hintLabel.isHidden = false
            hintLabel.text = "Tap to dictate"
            waveform.stop()
        case .listening:
            statusLabel.text = "Listening…"
            waveform.start()
        case .transcribing:
            statusLabel.text = "Transcribing…"
            waveform.stop()
        }
    }

    // MARK: - Actions

    @objc private func startListening() {
        requestTime = Date().timeIntervalSince1970
        gotAck = false
        bridge.clearResult()
        signal.post(DarwinSignal.recordStart)
        setMode(.listening)

        ackTimer?.invalidate()
        ackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self, !self.gotAck else { return }
            self.statusLabel.text = "Open the Handy app once"
            self.backToIdle(after: 1.6)
        }
        startPolling()
        armWatchdog(seconds: 50)
    }

    @objc private func confirmListening() {
        guard mode == .listening else { return }
        signal.post(DarwinSignal.recordStop)
        setMode(.transcribing)
        armWatchdog(seconds: 15)
    }

    @objc private func cancelListening() {
        signal.post(DarwinSignal.recordCancel)
        cancelTimers()
        setMode(.idle)
    }

    private func onAck() { gotAck = true; ackTimer?.invalidate() }

    // MARK: - Result

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tryInsertResult() }
    }

    private func tryInsertResult() {
        guard let (text, ts) = bridge.latestResult(), ts > requestTime else { return }
        let last = UserDefaults.standard.double(forKey: lastInsertedKey)
        guard ts > last else { return }
        cancelTimers()
        UserDefaults.standard.set(ts, forKey: lastInsertedKey)
        textDocumentProxy.insertText(text)
        bridge.clearResult()
        setMode(.idle)
        hintLabel.text = "Inserted ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if self?.mode == .idle { self?.hintLabel.text = "Tap to dictate" }
        }
    }

    private func backToIdle(after: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
            guard let self, self.mode != .idle else { return }
            self.cancelTimers(); self.setMode(.idle)
        }
    }

    private func armWatchdog(seconds: TimeInterval) {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.mode != .idle else { return }
            self.statusLabel.text = "Didn’t catch that"
            self.backToIdle(after: 1.2)
        }
    }

    private func cancelTimers() {
        pollTimer?.invalidate(); pollTimer = nil
        ackTimer?.invalidate(); ackTimer = nil
        watchdog?.invalidate(); watchdog = nil
    }
}

/// Animated waveform bars.
final class WaveBars: UIView {
    private let count = 21
    private var bars: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        bars = (0..<count).map { _ in
            let l = CALayer(); l.backgroundColor = UIColor.handyPinkDeep.cgColor; l.cornerRadius = 2
            layer.addSublayer(l); return l
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w: CGFloat = 4
        let gap = (bounds.width - CGFloat(count) * w) / CGFloat(count - 1)
        for (i, bar) in bars.enumerated() {
            let mid = Double(count - 1) / 2
            let d = abs(Double(i) - mid) / mid
            let base = bounds.height * CGFloat(0.25 + 0.75 * (1 - d))
            bar.frame = CGRect(x: CGFloat(i) * (w + gap), y: (bounds.height - base) / 2, width: w, height: base)
        }
    }

    func start() {
        for (i, bar) in bars.enumerated() {
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.25; a.toValue = 1.0
            a.duration = 0.32 + Double(i % 6) * 0.06
            a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(a, forKey: "p")
        }
    }
    func stop() { bars.forEach { $0.removeAllAnimations() } }
}
