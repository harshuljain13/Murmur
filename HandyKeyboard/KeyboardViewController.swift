import UIKit

/// Handy dictation bar. Recording + CPU transcription happen in the Handy app
/// running in the BACKGROUND (kept alive by a silent audio stream). The keyboard
/// triggers it via Darwin signals and inserts the transcript in place — no
/// app-switch. If the app is asleep, we show a hint (no jarring auto-launch).
final class KeyboardViewController: UIInputViewController {

    private let globeButton = UIButton(type: .system)
    private let micButton   = UIButton(type: .system)
    private let hintLabel   = UILabel()
    private let waveIcon    = WaveGlyph()

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
        tryInsertResult()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tryInsertResult()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if state == .listening { signal.post(DarwinSignal.recordStop) }
        cancelTimers()
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = .handyBackground

        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = UIColor.handyCream.withAlphaComponent(0.55)
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globeButton.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.text = "Tap to dictate"
        hintLabel.font = .systemFont(ofSize: 15, weight: .medium)
        hintLabel.textColor = UIColor.handyCream.withAlphaComponent(0.55)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        waveIcon.translatesAutoresizingMaskIntoConstraints = false

        var cfg = UIButton.Configuration.filled()
        cfg.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        cfg.baseBackgroundColor = .handyPinkDeep
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        micButton.configuration = cfg
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)

        [globeButton, waveIcon, hintLabel, micButton].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 66),
            globeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            globeButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            globeButton.widthAnchor.constraint(equalToConstant: 30),
            hintLabel.leadingAnchor.constraint(equalTo: globeButton.trailingAnchor, constant: 10),
            hintLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            waveIcon.leadingAnchor.constraint(equalTo: hintLabel.trailingAnchor, constant: 12),
            waveIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            waveIcon.heightAnchor.constraint(equalToConstant: 22),
            waveIcon.widthAnchor.constraint(equalToConstant: 46),
            micButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            micButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Mic

    @objc private func micTapped() {
        switch state {
        case .idle:         startListening()
        case .listening:    stopListening()
        case .transcribing: break
        }
    }

    private func startListening() {
        requestTime = Date().timeIntervalSince1970
        gotAck = false
        bridge.clearResult()
        signal.post(DarwinSignal.recordStart)

        state = .listening
        setMicActive(true)
        hint("Listening…")
        waveIcon.startIdleAnimation()

        ackTimer?.invalidate()
        ackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self, !self.gotAck else { return }
            self.resetToIdle(hint: "Open the Handy app once, then try again")
        }
        startPolling()
        armWatchdog(seconds: 50)
    }

    private func stopListening() {
        signal.post(DarwinSignal.recordStop)
        state = .transcribing
        setMicActive(false)
        hint("Transcribing…")
        waveIcon.stopIdleAnimation()
        armWatchdog(seconds: 15)
    }

    private func onAck() {
        gotAck = true
        ackTimer?.invalidate()
    }

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
        setMicActive(false)
        waveIcon.stopIdleAnimation()
        hint("Inserted ✓")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            if self?.state == .idle { self?.hint("Tap to dictate") }
        }
    }

    // MARK: - Timers / helpers

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
        setMicActive(false)
        waveIcon.stopIdleAnimation()
        if let text { hint(text) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.state == .idle { self?.hint("Tap to dictate") }
        }
    }

    private func setMicActive(_ active: Bool) {
        var cfg = micButton.configuration
        cfg?.image = UIImage(systemName: active ? "stop.fill" : "mic.fill",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        cfg?.baseBackgroundColor = active ? .systemRed : .handyPinkDeep
        micButton.configuration = cfg
    }

    private func hint(_ t: String) { hintLabel.text = t }
}

/// Small decorative waveform glyph; animates while listening.
final class WaveGlyph: UIView {
    private let bars: [CALayer] = (0..<7).map { _ in CALayer() }
    private let heights: [CGFloat] = [0.4, 0.75, 1.0, 0.55, 0.9, 0.5, 0.7]

    override init(frame: CGRect) {
        super.init(frame: frame)
        bars.forEach {
            $0.backgroundColor = UIColor.handyPink.withAlphaComponent(0.6).cgColor
            $0.cornerRadius = 1.5
            layer.addSublayer($0)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w: CGFloat = 3, gap: CGFloat = 4
        for (i, bar) in bars.enumerated() {
            let h = bounds.height * heights[i]
            bar.frame = CGRect(x: CGFloat(i) * (w + gap), y: (bounds.height - h) / 2, width: w, height: h)
        }
    }

    func startIdleAnimation() {
        for (i, bar) in bars.enumerated() {
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.4; a.toValue = 1.0
            a.duration = 0.4 + Double(i) * 0.05
            a.autoreverses = true
            a.repeatCount = .infinity
            bar.add(a, forKey: "pulse")
        }
    }
    func stopIdleAnimation() { bars.forEach { $0.removeAllAnimations() } }
}
