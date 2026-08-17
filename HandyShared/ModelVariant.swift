import Foundation

public enum ModelVariant: String, CaseIterable, Identifiable, Codable, Sendable {
    case parakeetQ4 = "parakeet-unified-en-0.6b-Q4_K_M"
    case parakeetQ8 = "parakeet-unified-en-0.6b-Q8_0"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .parakeetQ4: return "Parakeet Unified Q4"
        case .parakeetQ8: return "Parakeet Unified Q8"
        }
    }

    public var sizeDescription: String {
        switch self {
        case .parakeetQ4: return "477 MB · English · faster, recommended"
        case .parakeetQ8: return "731 MB · English · higher quality"
        }
    }

    public var isRecommended: Bool { self == .parakeetQ4 }

    /// Exact Content-Length in bytes — used to detect truncated/incomplete downloads.
    public var expectedBytes: Int64 {
        switch self {
        case .parakeetQ4: return 477_274_496
        case .parakeetQ8: return 731_357_568
        }
    }

    public var remoteURL: URL {
        switch self {
        case .parakeetQ4:
            return URL(string: "https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf/resolve/main/parakeet-unified-en-0.6b-Q4_K_M.gguf")!
        case .parakeetQ8:
            return URL(string: "https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf/resolve/main/parakeet-unified-en-0.6b-Q8_0.gguf")!
        }
    }

    public var filename: String { "\(rawValue).gguf" }
}
