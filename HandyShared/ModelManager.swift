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
    private var downloadTasks: [ModelVariant: URLSessionDownloadTask] = [:]

    public init() {}

    public func loadState() async {
        for variant in ModelVariant.allCases {
            if modelFileURL(for: variant) != nil {
                downloadStates[variant] = .ready
            } else {
                downloadStates[variant] = .notDownloaded
            }
        }
        activeModel = UserDefaults(suiteName: appGroup)?.string(forKey: "activeModel")
            .flatMap { ModelVariant(rawValue: $0) }
    }

    public func state(for variant: ModelVariant) -> ModelDownloadState {
        downloadStates[variant] ?? .notDownloaded
    }

    public func download(_ variant: ModelVariant) async {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return }

        let destURL = containerURL.appendingPathComponent("Models/\(variant.filename)")
        try? FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        downloadStates[variant] = .downloading(0)

        let (asyncBytes, response) = try! await URLSession.shared.bytes(from: variant.remoteURL)
        let totalBytes = response.expectedContentLength
        var downloadedBytes: Int64 = 0
        var buffer = Data()

        for try await byte in asyncBytes {
            buffer.append(byte)
            downloadedBytes += 1
            if downloadedBytes % 262_144 == 0 { // update every 256KB
                let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0
                downloadStates[variant] = .downloading(progress)
            }
        }

        try? buffer.write(to: destURL)
        downloadStates[variant] = .ready

        if activeModel == nil {
            setActive(variant)
        }
    }

    public func setActive(_ variant: ModelVariant) {
        activeModel = variant
        UserDefaults(suiteName: appGroup)?.set(variant.rawValue, forKey: "activeModel")
    }

    public func modelFileURL(for variant: ModelVariant) -> URL? {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let url = containerURL.appendingPathComponent("Models/\(variant.filename)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func activeModelFileURL() -> URL? {
        guard let active = activeModel else { return nil }
        return modelFileURL(for: active)
    }
}
