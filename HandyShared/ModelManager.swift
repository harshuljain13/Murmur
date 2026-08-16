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

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(from: variant.remoteURL)
            let totalBytes = response.expectedContentLength

            FileManager.default.createFile(atPath: destURL.path, contents: nil)
            let fileHandle = try FileHandle(forWritingTo: destURL)
            var received: Int64 = 0
            var chunk = Data(capacity: 512 * 1024)

            for try await byte in asyncBytes {
                chunk.append(byte)
                received += 1
                if chunk.count >= 512 * 1024 {
                    fileHandle.write(chunk)
                    chunk.removeAll(keepingCapacity: true)
                    if totalBytes > 0 {
                        downloadStates[variant] = .downloading(Double(received) / Double(totalBytes))
                    }
                }
            }
            if !chunk.isEmpty { fileHandle.write(chunk) }
            try fileHandle.close()

            downloadStates[variant] = .ready
            if activeModel == nil { setActive(variant) }
        } catch {
            downloadStates[variant] = .notDownloaded
            try? FileManager.default.removeItem(at: destURL)
        }
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

