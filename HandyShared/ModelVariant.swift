import Foundation

public enum ModelVariant: String, CaseIterable, Identifiable, Codable {
    case parakeetUnified = "parakeet-unified-en-0.6b-Q8_0"
    case whisperSmall = "ggml-small"
    case whisperMedium = "whisper-medium-q4_1"
    case whisperTurbo = "ggml-large-v3-turbo"
    case whisperLarge = "ggml-large-v3-q5_0"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .parakeetUnified: return "Parakeet Unified EN 0.6B (Recommended)"
        case .whisperSmall:    return "Whisper Small"
        case .whisperMedium:   return "Whisper Medium"
        case .whisperTurbo:    return "Whisper Turbo"
        case .whisperLarge:    return "Whisper Large"
        }
    }

    public var sizeDescription: String {
        switch self {
        case .parakeetUnified: return "731 MB · GGUF · English"
        case .whisperSmall:    return "487 MB · GGML"
        case .whisperMedium:   return "492 MB · GGML"
        case .whisperTurbo:    return "1.6 GB · GGML"
        case .whisperLarge:    return "1.1 GB · GGML"
        }
    }

    public var remoteURL: URL {
        switch self {
        case .parakeetUnified:
            return URL(string: "https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf/resolve/main/parakeet-unified-en-0.6b-Q8_0.gguf")!
        case .whisperSmall:
            return URL(string: "https://blob.handy.computer/ggml-small.bin")!
        case .whisperMedium:
            return URL(string: "https://blob.handy.computer/whisper-medium-q4_1.bin")!
        case .whisperTurbo:
            return URL(string: "https://blob.handy.computer/ggml-large-v3-turbo.bin")!
        case .whisperLarge:
            return URL(string: "https://blob.handy.computer/ggml-large-v3-q5_0.bin")!
        }
    }

    public var filename: String {
        switch self {
        case .parakeetUnified: return "parakeet-unified-en-0.6b-Q8_0.gguf"
        case .whisperSmall:    return "ggml-small.bin"
        case .whisperMedium:   return "whisper-medium-q4_1.bin"
        case .whisperTurbo:    return "ggml-large-v3-turbo.bin"
        case .whisperLarge:    return "ggml-large-v3-q5_0.bin"
        }
    }
}
