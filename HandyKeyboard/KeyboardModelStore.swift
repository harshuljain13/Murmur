import Foundation

/// Manages the Parakeet model file inside the keyboard extension's OWN container.
/// A free Apple account can't use App Groups, so the keyboard can't read the
/// main app's download — it keeps its own copy and inference runs in-process.
final class KeyboardModelStore: Sendable {

    // Q4 is the smallest Parakeet variant (~477MB) — best fit for the keyboard's
    // tighter memory budget.
    static let variant: ModelVariant = .parakeetQ4

    private var modelsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var modelURL: URL {
        modelsDir.appendingPathComponent(Self.variant.filename)
    }

    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    /// Streams the model to disk, reporting progress (0...1). The callback may
    /// be invoked on a background thread — hop to the main queue in the caller.
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let dest = modelURL
        let (bytes, response) = try await URLSession.shared.bytes(from: Self.variant.remoteURL)
        let total = response.expectedContentLength

        let tmp = dest.appendingPathExtension("part")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmp)

        var received: Int64 = 0
        var chunk = Data(capacity: 1 << 20)
        for try await byte in bytes {
            chunk.append(byte)
            received += 1
            if chunk.count >= (1 << 20) {
                handle.write(chunk)
                chunk.removeAll(keepingCapacity: true)
                if total > 0 { progress(Double(received) / Double(total)) }
            }
        }
        if !chunk.isEmpty { handle.write(chunk) }
        try handle.close()
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        progress(1.0)
    }
}
