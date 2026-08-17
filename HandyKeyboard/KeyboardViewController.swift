import UIKit

/// Handy dictation bar. Recording + CPU transcription happen in the Handy app
/// in the BACKGROUND; the keyboard triggers via Darwin signals and inserts the
/// transcript in place. Idle shows a mic pill; while listening it shows a
/// cancel ✕ / animated waveform / confirm ✓ row.
final class KeyboardViewController: UIInputViewController {

    private let globeButton  = UIButton(type: .system)
    private let hintLabel    = UILabel()

    // Idle
    private let micButton    = UIButton(type: .system)
    // Listening
    private let cancelButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)
    private let wavePill      = UIView()
    private let waveform      = WaveBars()

    private let bridge = TranscriptionBridge.shared
    private let signal = DarwinSignal.shared
    private let lastInsertedKey = "handy.lastInsertedTS"

    private enum State { case idle, listening, transcribing }
    private var state: State = .idle
    private var requestTime: TimeInterval = 0
    private var gotAck = false
    private var pollTimer: Timer?
    private var ackTimer: Timer?
    private var watchdog: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        signal.observe(DarwinSignal.recordAck)   { [weak self] in self?.onAck() }
        signal.observe(DarwinSignal.resultReady) { [weak self] in self?.tryInsertResult() }
        applyState()
        tryInsertResult()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tryInsertResult()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if state == .listening { signal.post(DarwinSignal.recordCancel) }
        cancelTimers()
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = .handyBackground

        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = UIColor.handyCream.withAlphaComponent(0.5)
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globeButton.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.text = "Tap to dictate"
        hintLabel.font = .systemFont(ofSize: 15, weight: .medium)
        hintLabel.textColor = UIColor.handyCream.withAlphaComponent(0.5)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        // Idle mic pill
        var micCfg = UIButton.Configuration.filled()
        micCfg.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        micCfg.baseBackgroundColor = .handyPinkDeep
        micCfg.baseForegroundColor = .white
        micCfg.cornerStyle = .capsule
        micCfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 34, bottom: 14, trailing: 34)
        micButton.configuration = micCfg
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.addTarget(self, action: #selector(startListening), for: .touchUpInside)

        // Cancel ✕ (light circle)
        cancelButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)), for: .normal)
        cancelButton.tintColor = UIColor.handyCream.withAlphaComponent(0.8)
        cancelButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        cancelButton.layer.cornerRadius = 24
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelListening), for: .touchUpInside)

        // Waveform pill (pink-tinted capsule)
        wavePill.backgroundColor = UIColor.handyPink.withAlphaComponent(0.16)
        wavePill.layer.cornerRadius = 24
        wavePill.translatesAutoresizingMaskIntoConstraints = false
        waveform.translatesAutoresizingMaskIntoConstraints = false
        wavePill.addSubview(waveform)

        // Confirm ✓ (pink circle)
        confirmButton.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)), for: .normal)
        confirmButton.tintColor = .white
        confirmButton.backgroundColor = .handyPinkDeep
        confirmButton.layer.cornerRadius = 24
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(confirmListening), for: .touchUpInside)

        [globeButton, hintLabel, micButton, cancelButton, wavePill, confirmButton].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 84),

            globeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            globeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            globeButton.widthAnchor.constraint(equalToConstant: 28),

            // Idle: mic centered, hint below
            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -6),
            hintLabel.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 8),
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Listening row: [✕] [waveform] [✓] centered
            confirmButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            confirmButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            confirmButton.widthAnchor.constraint(equalToConstant: 48),
            confirmButton.heightAnchor.constraint(equalToConstant: 48),

            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 48),
            cancelButton.heightAnchor.constraint(equalToConstant: 48),

            wavePill.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 12),
            wavePill.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -12),
            wavePill.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            wavePill.heightAnchor.constraint(equalToConstant: 48),

            waveform.centerXAnchor.constraint(equalTo: wavePill.centerXAnchor),
            waveform.centerYAnchor.constraint(equalTo: wavePill.centerYAnchor),
            waveform.heightAnchor.constraint(equalToConstant: 22),
            waveform.widthAnchor.constraint(equalTo: wavePill.widthAnchor, multiplier: 0.7),
        ])
    }

    private func applyState() {
        let listening = (state == .listening || state == .transcribing)
        micButton.isHidden = listening
        hintLabel.isHidden = listening && state == .listening
        cancelButton.isHidden = !listening
        wavePill.isHidden = !listening
        confirmButton.isHidden = !listening

        switch state {
        case .idle:
            hintLabel.isHidden = false
            hintLabel.text = "Tap to dictate"
            waveform.stop()
        case .listening:
            waveform.start()
        case .transcribing:
            hintLabel.isHidden = false
            hintLabel.text = "Transcribing…"
            waveform.stop()
        }
    }

    // MARK: - Actions

    @objc private func startListening() {
        requestTime = Date().timeIntervalSince1970
        gotAck = false
        bridge.clearResult()
        signal.post(DarwinSignal.recordStart)
        state = .listening
        applyState()

        ackTimer?.invalidate()
        ackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self, !self.gotAck else { return }
            self.resetToIdle(hint: "Open the Handy app once, then try again")
        }
        startPolling()
        armWatchdog(seconds: 50)
    }

    @objc private func confirmListening() {
        guard state == .listening else { return }
        signal.post(DarwinSignal.recordStop)
        state = .transcribing
        applyState()
        armWatchdog(seconds: 15)
    }

    @objc private func cancelListening() {
        signal.post(DarwinSignal.recordCancel)
        resetToIdle(hint: nil)
    }

    private func onAck() { gotAck = true; ackTimer?.invalidate() }

    // MARK: - Result

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tryInsertResult()
        }
    }

    private func tryInsertResult() {
        guard let (text, ts) = bridge.latestResult(), ts > requestTime else { return }
        let last = UserDefaults.standard.double(forKey: lastInsertedKey)
        guard ts > last else { return }
        cancelTimers()
        UserDefaults.standard.set(ts, forKey: lastInsertedKey)
        textDocumentProxy.insertText(text)
        bridge.clearResult()
        state = .idle
        applyState()
        hintLabel.text = "Inserted ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if self?.state == .idle { self?.hintLabel.text = "Tap to dictate" }
        }
    }

    // MARK: - Timers

    private func armWatchdog(seconds: TimeInterval) {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.state != .idle else { return }
            self.resetToIdle(hint: "Didn’t catch that — tap to retry")
        }
    }

    private func cancelTimers() {
        pollTimer?.invalidate(); pollTimer = nil
        ackTimer?.invalidate(); ackTimer = nil
        watchdog?.invalidate(); watchdog = nil
    }

    private func resetToIdle(hint text: String?) {
        cancelTimers()
        state = .idle
        applyState()
        if let text { hintLabel.text = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.state == .idle { self?.hintLabel.text = "Tap to dictate" }
        }
    }
}

/// Animated waveform bars for the listening pill.
final class WaveBars: UIView {
    private let count = 13
    private var bars: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        bars = (0..<count).map { _ in
            let l = CALayer()
            l.backgroundColor = UIColor.handyPinkDeep.cgColor
            l.cornerRadius = 1.5
            layer.addSublayer(l)
            return l
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w: CGFloat = 3
        let gap = (bounds.width - CGFloat(count) * w) / CGFloat(count - 1)
        for (i, bar) in bars.enumerated() {
            let base = bounds.height * baseHeight(i)
            bar.frame = CGRect(x: CGFloat(i) * (w + gap), y: (bounds.height - base) / 2, width: w, height: base)
        }
    }

    private func baseHeight(_ i: Int) -> CGFloat {
        let mid = Double(count - 1) / 2
        let d = abs(Double(i) - mid) / mid          // 0 center … 1 edges
        return CGFloat(0.35 + 0.65 * (1 - d))        // taller in the middle
    }

    func start() {
        for (i, bar) in bars.enumerated() {
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.35
            a.toValue = 1.0
            a.duration = 0.35 + Double(i % 4) * 0.08
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(a, forKey: "pulse")
        }
    }
    func stop() { bars.forEach { $0.removeAllAnimations() } }
}
