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
        if activeModel == nil, let ready = ModelVariant.allCases.first(where: { fileExists(for: $0) }) {
            setActive(ready)
        }
    }

    public func state(for variant: ModelVariant) -> ModelDownloadState {
        downloadStates[variant] ?? .notDownloaded
    }

    public func download(_ variant: ModelVariant) async {
        guard let destURL = modelFileURL(for: variant, mustExist: false) else { return }
        try? FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        downloadStates[variant] = .downloading(0)

        let delegate = DownloadProgressDelegate { @Sendable [weak self] progress in
            Task { @MainActor in self?.downloadStates[variant] = .downloading(progress) }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
            let (tempURL, _) = try await session.download(from: variant.remoteURL)
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.moveItem(at: tempURL, to: destURL)
            downloadStates[variant] = .ready
            if activeModel == nil { setActive(variant) }
        } catch {
            downloadStates[variant] = .notDownloaded
        }
        session.invalidateAndCancel()
    }

    public func setActive(_ variant: ModelVariant) {
        activeModel = variant
        defaults.set(variant.rawValue, forKey: "activeModel")
    }

    public func activeModelFileURL() -> URL? {
        guard let active = activeModel else { return nil }
        return modelFileURL(for: active, mustExist: true)
    }

    // MARK: - Storage

    /// Tries App Group container first; falls back to app Documents if not entitled.
    private var modelsBaseURL: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return groupURL.appendingPathComponent("Models")
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models")
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    private func fileExists(for variant: ModelVariant) -> Bool {
        modelFileURL(for: variant, mustExist: true) != nil
    }

    private func modelFileURL(for variant: ModelVariant, mustExist: Bool) -> URL? {
        let url = modelsBaseURL.appendingPathComponent(variant.filename)
        if mustExist && !FileManager.default.fileExists(atPath: url.path) { return nil }
        return url
    }

    private func savedActiveModel() -> ModelVariant? {
        defaults.string(forKey: "activeModel").flatMap { ModelVariant(rawValue: $0) }
    }
}

// URLSessionDownloadDelegate to track download progress
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Double) -> Void
    init(_ onProgress: @Sendable @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Handled in the async/await call site
    }
}
