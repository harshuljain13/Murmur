import UIKit

/// Handy dictation bar. GPU transcription requires the foreground, so the mic
/// button opens the Handy app (which records + transcribes with a waveform),
/// then the transcript is inserted here when the user returns.
final class KeyboardViewController: UIInputViewController {

    private let globeButton = UIButton(type: .system)
    private let micButton   = UIButton(type: .system)
    private let hintLabel   = UILabel()
    private let waveIcon    = WaveGlyph()

    private let bridge = TranscriptionBridge.shared
    private let lastInsertedKey = "handy.lastInsertedTS"

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        insertPendingResultIfAny()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        insertPendingResultIfAny()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        insertPendingResultIfAny()
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

    // MARK: - Actions

    @objc private func micTapped() {
        hintLabel.text = "Opening Handy…"
        waveIcon.startIdleAnimation()

        let url = URL(string: "handy://record")!
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:]) { [weak self] ok in
                    if !ok { self?.hintLabel.text = "Enable ‘Allow Full Access’" }
                }
                return
            }
            responder = r.next
        }
        hintLabel.text = "Enable ‘Allow Full Access’"
    }

    /// Insert a fresh transcript on return. Uses a persisted timestamp so it
    /// survives the keyboard extension being terminated while Handy was open.
    private func insertPendingResultIfAny() {
        guard let (text, ts) = bridge.latestResult() else { return }
        let last = UserDefaults.standard.double(forKey: lastInsertedKey)
        guard ts > last else { return }

        textDocumentProxy.insertText(text)
        UserDefaults.standard.set(ts, forKey: lastInsertedKey)
        bridge.clearResult()

        waveIcon.stopIdleAnimation()
        hintLabel.text = "Inserted ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.hintLabel.text = "Tap to dictate"
        }
    }
}

/// Small decorative waveform glyph shown in the bar; animates while waiting.
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
