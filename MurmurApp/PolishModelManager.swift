import Foundation

/// Downloads + tracks the Qwen polish model.
@MainActor
final class PolishModelManager: ObservableObject {
    enum State: Equatable { case notDownloaded, downloading(Double), ready }
    @Published var state: State = .notDownloaded

    func refresh() {
        state = PolishService.isModelDownloaded ? .ready : .notDownloaded
    }

    func download() async {
        let dest = PolishService.modelPath
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        state = .downloading(0)

        let dl = ModelDownloader()
        do {
            let tmp = try await dl.download(from: PolishService.modelURL) { [weak self] p in
                Task { @MainActor in self?.state = .downloading(p) }
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64) ?? 0
            guard size >= Int64(Double(PolishService.modelExpectedBytes) * 0.99) else {
                try? FileManager.default.removeItem(at: tmp)
                state = .notDownloaded
                return
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            state = .ready
        } catch {
            state = .notDownloaded
        }
    }
}
