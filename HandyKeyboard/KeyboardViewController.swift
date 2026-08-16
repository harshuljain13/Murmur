import UIKit

/// Thin client. iOS forbids microphone access inside keyboard extensions, so the
/// mic button hands off to the Handy app (handy://record), which records +
/// transcribes. When the user returns here, we insert the transcript.
final class KeyboardViewController: UIInputViewController {

    private let globeButton = UIButton(type: .system)
    private let micButton   = UIButton(type: .system)
    private let statusLabel = UILabel()

    private let bridge = TranscriptionBridge.shared
    private var pollTimer: Timer?
    private var awaitingResult = false
    private var requestTime: TimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Returning from the Handy app — insert any fresh transcript.
        insertPendingResultIfAny()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        // Also catch the case where the keyboard re-activates in the host app.
        insertPendingResultIfAny()
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)

        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.tintColor = UIColor.white.withAlphaComponent(0.5)
        globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globeButton.translatesAutoresizingMaskIntoConstraints = false

        micButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26)), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        micButton.layer.cornerRadius = 34
        micButton.clipsToBounds = true
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)

        statusLabel.text = "Tap mic to dictate"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        [globeButton, micButton, statusLabel].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 180),

            globeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            globeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -8),
            micButton.widthAnchor.constraint(equalToConstant: 68),
            micButton.heightAnchor.constraint(equalToConstant: 68),

            statusLabel.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    // MARK: - Actions

    @objc private func micTapped() {
        bridge.clearResult()
        requestTime = Date().timeIntervalSince1970
        awaitingResult = true
        setStatus("Opening Handy…")

        // Open the main app to record (only the app can use the mic on iOS).
        // Requires Full Access. Walk the responder chain to UIApplication and
        // use the modern open(_:options:completionHandler:).
        let url = URL(string: "handy://record")!
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:]) { [weak self] success in
                    if !success {
                        self?.setStatus("Enable 'Allow Full Access' for Handy")
                    }
                }
                return
            }
            responder = r.next
        }
        setStatus("Couldn't open Handy — enable Full Access")
    }

    private func insertPendingResultIfAny() {
        guard awaitingResult else { return }
        if let text = bridge.readResult(newerThan: requestTime) {
            awaitingResult = false
            textDocumentProxy.insertText(text)
            bridge.clearResult()
            setStatus("Inserted ✓")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.setStatus("Tap mic to dictate")
            }
        }
    }

    private func setStatus(_ text: String) {
        statusLabel.text = text
    }
}
