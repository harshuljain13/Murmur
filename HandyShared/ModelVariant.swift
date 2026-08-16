import Foundation

public enum ModelVariant: String, CaseIterable, Identifiable, Codable, Sendable {
    case parakeetQ4    = "parakeet-unified-en-0.6b-Q4_K_M"
    case parakeetQ8    = "parakeet-unified-en-0.6b-Q8_0"
    case nemotron      = "nemotron-3.5-asr-streaming-0.6b-Q8_0"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .parakeetQ4:  return "Parakeet Unified Q4"
        case .parakeetQ8:  return "Parakeet Unified Q8"
        case .nemotron:    return "Nemotron 3.5 Streaming"
        }
    }

    public var sizeDescription: String {
        switch self {
        case .parakeetQ4:  return "477 MB · English · faster"
        case .parakeetQ8:  return "731 MB · English · better quality"
        case .nemotron:    return "~700 MB · 28 languages · streaming"
        }
    }

    public var isRecommended: Bool {
        self == .parakeetQ8
    }

    public var remoteURL: URL {
        switch self {
        case .parakeetQ4:
            return URL(string: "https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf/resolve/main/parakeet-unified-en-0.6b-Q4_K_M.gguf")!
        case .parakeetQ8:
            return URL(string: "https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf/resolve/main/parakeet-unified-en-0.6b-Q8_0.gguf")!
        case .nemotron:
            return URL(string: "https://huggingface.co/handy-computer/nemotron-3.5-asr-streaming-0.6b-gguf/resolve/main/nemotron-3.5-asr-streaming-0.6b-Q8_0.gguf")!
        }
    }

    public var filename: String { "\(rawValue).gguf" }
}
