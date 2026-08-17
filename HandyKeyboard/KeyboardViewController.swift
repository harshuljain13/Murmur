import UIKit

/// A full QWERTY keyboard with a mic button in the top-right toolbar. Tapping the
/// mic swaps the letter keys for a dictation bar (✕ cancel · waveform · ✓ confirm)
/// on the same light background. Recording + CPU transcription run in the Handy
/// app in the background; the transcript is inserted in place.
final class KeyboardViewController: UIInputViewController {

    // Palette (light, system-like)
    private let kbBackground   = UIColor(red: 209/255, green: 212/255, blue: 219/255, alpha: 1)
    private let keyFill        = UIColor.white
    private let keyModifier    = UIColor(red: 172/255, green: 178/255, blue: 189/255, alpha: 1)
    private let keyText        = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
    private let pink           = UIColor.handyPinkDeep

    private var shifted = true
    private var symbols = false
    private var letterButtons: [UIButton] = []

    private let keyboardStack = UIStackView()   // the QWERTY area
    private let dictationBar = UIView()          // shown while dictating
    private let waveform = WaveBars()
    private let confirmButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    // IPC
    private let bridge = TranscriptionBridge.shared
    private let signal = DarwinSignal.shared
    private let lastInsertedKey = "handy.lastInsertedTS"
    private enum Mode { case typing, listening, transcribing }
    private var mode: Mode = .typing
    private var requestTime: TimeInterval = 0
    private var gotAck = false
    private var pollTimer: Timer?, ackTimer: Timer?, watchdog: Timer?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = kbBackground
        buildKeyboard()
        buildDictationBar()
        signal.observe(DarwinSignal.recordAck)   { [weak self] in self?.onAck() }
        signal.observe(DarwinSignal.resultReady) { [weak self] in self?.tryInsertResult() }
        showTyping()
        tryInsertResult()
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); tryInsertResult() }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if mode == .listening { signal.post(DarwinSignal.recordCancel) }
        cancelTimers()
    }

    // MARK: - Build keyboard

    private func buildKeyboard() {
        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fillEqually
        keyboardStack.spacing = 8
        keyboardStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardStack)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 258),
            keyboardStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            keyboardStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            keyboardStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            keyboardStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])
        renderKeys()
    }

    private func renderKeys() {
        keyboardStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        letterButtons.removeAll()

        // Toolbar: mic on the right
        let toolbar = UIStackView()
        toolbar.axis = .horizontal
        toolbar.alignment = .center
        let spacer = UIView()
        var micCfg = UIButton.Configuration.filled()
        micCfg.image = UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        micCfg.baseBackgroundColor = pink
        micCfg.baseForegroundColor = .white
        micCfg.cornerStyle = .capsule
        micCfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
        let mic = UIButton(configuration: micCfg)
        mic.addTarget(self, action: #selector(startListening), for: .touchUpInside)
        let hint = UILabel()
        hint.text = "Handy — tap to dictate →"
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = keyText.withAlphaComponent(0.45)
        toolbar.addArrangedSubview(hint)
        toolbar.addArrangedSubview(spacer)
        toolbar.addArrangedSubview(mic)
        keyboardStack.addArrangedSubview(toolbar)
        toolbar.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let rows: [[String]]
        if symbols {
            rows = [["1","2","3","4","5","6","7","8","9","0"],
                    ["-","/",":",";","(",")","$","&","@","\""],
                    [".",",","?","!","'"]]
        } else {
            rows = [["q","w","e","r","t","y","u","i","o","p"],
                    ["a","s","d","f","g","h","j","k","l"],
                    ["z","x","c","v","b","n","m"]]
        }

        keyboardStack.addArrangedSubview(letterRow(rows[0]))
        keyboardStack.addArrangedSubview(indentedRow(rows[1]))
        keyboardStack.addArrangedSubview(thirdRow(rows[2]))
        keyboardStack.addArrangedSubview(bottomRow())
    }

    private func letterRow(_ keys: [String]) -> UIStackView {
        let row = hStack()
        keys.forEach { row.addArrangedSubview(letterKey($0)) }
        return row
    }

    private func indentedRow(_ keys: [String]) -> UIStackView {
        let row = hStack()
        let l = UIView(), r = UIView()
        l.widthAnchor.constraint(equalTo: r.widthAnchor).isActive = true
        row.addArrangedSubview(l)
        keys.forEach { row.addArrangedSubview(letterKey($0)) }
        row.addArrangedSubview(r)
        return row
    }

    private func thirdRow(_ keys: [String]) -> UIStackView {
        let row = hStack()
        let shift = modifierKey(symbols ? "#+=" : "⇧", action: #selector(toggleShift))
        row.addArrangedSubview(shift)
        shift.widthAnchor.constraint(equalToConstant: 42).isActive = true
        keys.forEach { row.addArrangedSubview(letterKey($0)) }
        let del = modifierKey("⌫", action: #selector(deleteTap))
        del.widthAnchor.constraint(equalToConstant: 42).isActive = true
        row.addArrangedSubview(del)
        return row
    }

    private func bottomRow() -> UIStackView {
        let row = hStack()
        let mode123 = modifierKey(symbols ? "ABC" : "123", action: #selector(toggleSymbols))
        mode123.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let globe = modifierKey("🌐", action: #selector(nextKeyboard))
        globe.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let space = letterKey("space"); space.setTitle("space", for: .normal)
        space.removeTarget(nil, action: nil, for: .allEvents)
        space.addTarget(self, action: #selector(spaceTap), for: .touchUpInside)
        let ret = modifierKey("return", action: #selector(returnTap))
        ret.widthAnchor.constraint(equalToConstant: 90).isActive = true
        row.addArrangedSubview(mode123)
        row.addArrangedSubview(globe)
        row.addArrangedSubview(space)
        row.addArrangedSubview(ret)
        return row
    }

    private func hStack() -> UIStackView {
        let s = UIStackView(); s.axis = .horizontal; s.distribution = .fillProportionally; s.spacing = 6; s.alignment = .fill
        return s
    }

    private func letterKey(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(shifted && !symbols ? title.uppercased() : title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 22)
        b.setTitleColor(keyText, for: .normal)
        b.backgroundColor = keyFill
        b.layer.cornerRadius = 6
        b.layer.shadowColor = UIColor.black.cgColor
        b.layer.shadowOpacity = 0.28
        b.layer.shadowOffset = CGSize(width: 0, height: 1)
        b.layer.shadowRadius = 0
        b.addTarget(self, action: #selector(letterTap(_:)), for: .touchUpInside)
        letterButtons.append(b)
        return b
    }

    private func modifierKey(_ title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: title.count > 2 ? 16 : 20)
        b.setTitleColor(keyText, for: .normal)
        b.backgroundColor = keyModifier
        b.layer.cornerRadius = 6
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    // MARK: - Key actions

    @objc private func letterTap(_ sender: UIButton) {
        guard let t = sender.currentTitle else { return }
        textDocumentProxy.insertText(t)
        if shifted && !symbols { shifted = false; refreshCaps() }
    }
    @objc private func spaceTap() { textDocumentProxy.insertText(" ") }
    @objc private func returnTap() { textDocumentProxy.insertText("\n") }
    @objc private func deleteTap() { textDocumentProxy.deleteBackward() }
    @objc private func toggleShift() { shifted.toggle(); refreshCaps() }
    @objc private func toggleSymbols() { symbols.toggle(); shifted = false; renderKeys() }
    @objc private func nextKeyboard() { advanceToNextInputMode() }

    private func refreshCaps() {
        for b in letterButtons {
            guard let t = b.currentTitle, t.count == 1, t.rangeOfCharacter(from: .letters) != nil else { continue }
            b.setTitle(shifted ? t.uppercased() : t.lowercased(), for: .normal)
        }
    }

    // MARK: - Dictation bar

    private func buildDictationBar() {
        dictationBar.translatesAutoresizingMaskIntoConstraints = false
        dictationBar.backgroundColor = kbBackground
        dictationBar.isHidden = true
        view.addSubview(dictationBar)
        NSLayoutConstraint.activate([
            dictationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dictationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dictationBar.topAnchor.constraint(equalTo: view.topAnchor),
            dictationBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        cancelButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)), for: .normal)
        cancelButton.tintColor = keyText.withAlphaComponent(0.7)
        cancelButton.backgroundColor = keyModifier
        cancelButton.layer.cornerRadius = 26
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelListening), for: .touchUpInside)

        let pill = UIView()
        pill.backgroundColor = pink.withAlphaComponent(0.12)
        pill.layer.cornerRadius = 26
        pill.translatesAutoresizingMaskIntoConstraints = false
        waveform.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(waveform)

        confirmButton.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)), for: .normal)
        confirmButton.tintColor = .white
        confirmButton.backgroundColor = pink
        confirmButton.layer.cornerRadius = 26
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(self, action: #selector(confirmListening), for: .touchUpInside)

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = keyText.withAlphaComponent(0.5)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        [cancelButton, pill, confirmButton, statusLabel].forEach { dictationBar.addSubview($0) }
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: dictationBar.leadingAnchor, constant: 22),
            cancelButton.centerYAnchor.constraint(equalTo: dictationBar.centerYAnchor, constant: -10),
            cancelButton.widthAnchor.constraint(equalToConstant: 52),
            cancelButton.heightAnchor.constraint(equalToConstant: 52),

            confirmButton.trailingAnchor.constraint(equalTo: dictationBar.trailingAnchor, constant: -22),
            confirmButton.centerYAnchor.constraint(equalTo: dictationBar.centerYAnchor, constant: -10),
            confirmButton.widthAnchor.constraint(equalToConstant: 52),
            confirmButton.heightAnchor.constraint(equalToConstant: 52),

            pill.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 14),
            pill.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -14),
            pill.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 52),
            waveform.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            waveform.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            waveform.heightAnchor.constraint(equalToConstant: 24),
            waveform.widthAnchor.constraint(equalTo: pill.widthAnchor, multiplier: 0.72),

            statusLabel.topAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 14),
            statusLabel.centerXAnchor.constraint(equalTo: dictationBar.centerXAnchor),
        ])
    }

    private func showTyping() {
        mode = .typing
        keyboardStack.isHidden = false
        dictationBar.isHidden = true
        waveform.stop()
    }

    private func showDictation(_ status: String) {
        keyboardStack.isHidden = true
        dictationBar.isHidden = false
        statusLabel.text = status
    }

    // MARK: - Dictation actions

    @objc private func startListening() {
        requestTime = Date().timeIntervalSince1970
        gotAck = false
        bridge.clearResult()
        signal.post(DarwinSignal.recordStart)
        mode = .listening
        showDictation("Listening…")
        waveform.start()

        ackTimer?.invalidate()
        ackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self, !self.gotAck else { return }
            self.statusLabel.text = "Open the Handy app once"
            self.finishToTyping(after: 1.6)
        }
        startPolling()
        armWatchdog(seconds: 50)
    }

    @objc private func confirmListening() {
        guard mode == .listening else { return }
        signal.post(DarwinSignal.recordStop)
        mode = .transcribing
        statusLabel.text = "Transcribing…"
        waveform.stop()
        armWatchdog(seconds: 15)
    }

    @objc private func cancelListening() {
        signal.post(DarwinSignal.recordCancel)
        cancelTimers()
        showTyping()
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
        showTyping()
    }

    private func finishToTyping(after: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
            guard let self, self.mode != .typing else { return }
            self.cancelTimers(); self.showTyping()
        }
    }

    private func armWatchdog(seconds: TimeInterval) {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self, self.mode != .typing else { return }
            self.statusLabel.text = "Didn’t catch that"
            self.finishToTyping(after: 1.2)
        }
    }

    private func cancelTimers() {
        pollTimer?.invalidate(); pollTimer = nil
        ackTimer?.invalidate(); ackTimer = nil
        watchdog?.invalidate(); watchdog = nil
    }
}

/// Animated waveform bars for the dictation pill.
final class WaveBars: UIView {
    private let count = 15
    private var bars: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        bars = (0..<count).map { _ in
            let l = CALayer(); l.backgroundColor = UIColor.handyPinkDeep.cgColor; l.cornerRadius = 1.5
            layer.addSublayer(l); return l
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w: CGFloat = 3
        let gap = (bounds.width - CGFloat(count) * w) / CGFloat(count - 1)
        for (i, bar) in bars.enumerated() {
            let mid = Double(count - 1) / 2
            let d = abs(Double(i) - mid) / mid
            let base = bounds.height * CGFloat(0.3 + 0.7 * (1 - d))
            bar.frame = CGRect(x: CGFloat(i) * (w + gap), y: (bounds.height - base) / 2, width: w, height: base)
        }
    }

    func start() {
        for (i, bar) in bars.enumerated() {
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 0.3; a.toValue = 1.0
            a.duration = 0.34 + Double(i % 5) * 0.07
            a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(a, forKey: "p")
        }
    }
    func stop() { bars.forEach { $0.removeAllAnimations() } }
}
