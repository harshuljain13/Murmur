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

    private var downloader: ModelDownloader?

    public init() {}

    public func loadState() async {
        for variant in ModelVariant.allCases {
            // Only a COMPLETE file (size matches expected) counts as ready.
            // Delete truncated leftovers from interrupted downloads.
            if isComplete(variant) {
                downloadStates[variant] = .ready
            } else {
                deleteFile(variant)
                downloadStates[variant] = .notDownloaded
            }
        }
        activeModel = savedActiveModel()
        if activeModel == nil, let ready = ModelVariant.allCases.first(where: { isComplete($0) }) {
            setActive(ready)
        } else if let active = activeModel, !isComplete(active) {
            // Previously-active model is gone/corrupt — clear it.
            activeModel = nil
            UserDefaults.standard.removeObject(forKey: "activeModel")
        }
    }

    public func state(for variant: ModelVariant) -> ModelDownloadState {
        downloadStates[variant] ?? .notDownloaded
    }

    public func download(_ variant: ModelVariant) async {
        let dest = fileURL(for: variant)
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        deleteFile(variant) // clear any partial leftover

        downloadStates[variant] = .downloading(0)

        let dl = ModelDownloader()
        downloader = dl
        do {
            let tempURL = try await dl.download(from: variant.remoteURL) { [weak self] p in
                Task { @MainActor in self?.downloadStates[variant] = .downloading(p) }
            }
            // Verify completeness before finalizing.
            let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
            guard size >= Int64(Double(variant.expectedBytes) * 0.99) else {
                try? FileManager.default.removeItem(at: tempURL)
                downloadStates[variant] = .notDownloaded
                return
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            downloadStates[variant] = .ready
            if activeModel == nil { setActive(variant) }
        } catch {
            downloadStates[variant] = .notDownloaded
        }
        downloader = nil
    }

    public func setActive(_ variant: ModelVariant) {
        activeModel = variant
        UserDefaults.standard.set(variant.rawValue, forKey: "activeModel")
    }

    public func activeModelFileURL() -> URL? {
        guard let active = activeModel, isComplete(active) else { return nil }
        return fileURL(for: active)
    }

    // MARK: - Storage helpers

    private var modelsBaseURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Models")
    }

    private func fileURL(for variant: ModelVariant) -> URL {
        modelsBaseURL.appendingPathComponent(variant.filename)
    }

    private func isComplete(_ variant: ModelVariant) -> Bool {
        let url = fileURL(for: variant)
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 else { return false }
        return size >= Int64(Double(variant.expectedBytes) * 0.99)
    }

    private func deleteFile(_ variant: ModelVariant) {
        try? FileManager.default.removeItem(at: fileURL(for: variant))
    }

    private func savedActiveModel() -> ModelVariant? {
        UserDefaults.standard.string(forKey: "activeModel").flatMap { ModelVariant(rawValue: $0) }
    }
}

/// Downloads a large file to disk at native speed using URLSessionDownloadTask,
/// reporting progress. `didFinishDownloadingTo` only fires on a COMPLETE download.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: (@Sendable (Double) -> Void)?
    private var savedURL: URL?

    func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        self.progressHandler = progress
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move to a stable temp path synchronously — `location` is deleted on return.
        let stable = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur_dl_\(UUID().uuidString).gguf")
        do {
            try FileManager.default.moveItem(at: location, to: stable)
            savedURL = stable
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error) }
        else if let savedURL { continuation?.resume(returning: savedURL) }
        else { continuation?.resume(throwing: URLError(.cannotOpenFile)) }
        continuation = nil
        session.invalidateAndCancel()
    }
}
