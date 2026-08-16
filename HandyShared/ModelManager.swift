import Foundation

public enum ModelDownloadState {
    case notDownloaded
    case downloading(Double)
    case ready
}

@MainActor
public final class ModelManager: ObservableObject {
    @Published private var downloadStates: [ModelVariant: ModelDownloadState] = [:]
    @Published public var activeModel: ModelVariant?

    private let appGroup = "group.computer.handy"

    public init() {}

    public func loadState() async {
        for variant in ModelVariant.allCases {
            downloadStates[variant] = fileExists(for: variant) ? .ready : .notDownloaded
        }
        activeModel = savedActiveModel()

        // Auto-select first ready model if none saved
        if activeModel == nil, let ready = ModelVariant.allCases.first(where: { fileExists(for: $0) }) {
            setActive(ready)
        }
    }

    public func state(for variant: ModelVariant) -> ModelDownloadState {
        downloadStates[variant] ?? .notDownloaded
    }

    public func download(_ variant: ModelVariant) async {
        guard let destURL = modelFileURL(for: variant, mustExist: false) else { return }
        try? FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        downloadStates[variant] = .downloading(0)

        let (tempURL, _) = try! await URLSession.shared.download(
            for: URLRequest(url: variant.remoteURL),
            delegate: ProgressDelegate { [weak self] progress in
                Task { @MainActor in self?.downloadStates[variant] = .downloading(progress) }
            }
        )

        try? FileManager.default.moveItem(at: tempURL, to: destURL)
        downloadStates[variant] = .ready

        if activeModel == nil { setActive(variant) }
    }

    public func setActive(_ variant: ModelVariant) {
        activeModel = variant
        UserDefaults(suiteName: appGroup)?.set(variant.rawValue, forKey: "activeModel")
    }

    public func activeModelFileURL() -> URL? {
        guard let active = activeModel else { return nil }
        return modelFileURL(for: active, mustExist: true)
    }

    private func fileExists(for variant: ModelVariant) -> Bool {
        modelFileURL(for: variant, mustExist: true) != nil
    }

    private func modelFileURL(for variant: ModelVariant, mustExist: Bool) -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let url = base.appendingPathComponent("Models/\(variant.filename)")
        if mustExist && !FileManager.default.fileExists(atPath: url.path) { return nil }
        return url
    }

    private func savedActiveModel() -> ModelVariant? {
        UserDefaults(suiteName: appGroup)?.string(forKey: "activeModel").flatMap { ModelVariant(rawValue: $0) }
    }
}

// URLSession download progress via delegate
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Double) -> Void
    init(_ onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {}

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}
