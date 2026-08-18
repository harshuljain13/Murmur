import Foundation

/// Swift wrapper around the llama.cpp `handy_llm_*` C API (Qwen2.5-0.5B).
/// Not thread-safe — drive it from a single actor.
final class LlamaPolisher {
    private var handle: OpaquePointer?

    init?(modelPath: String) {
        let threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount))
        handle = handy_llm_load(modelPath, threads)
        if handle == nil { return nil }
    }

    deinit { if let h = handle { handy_llm_free(h) } }

    func rewrite(system: String, text: String, maxTokens: Int32 = 200) -> String? {
        guard let h = handle else { return nil }
        guard let c = handy_llm_rewrite(h, system, text, maxTokens) else { return nil }
        defer { handy_llm_free_string(c) }
        return String(cString: c)
    }
}

/// Serializes access to the (heavy, non-reentrant) LLM.
actor LlamaEngine {
    private var polisher: LlamaPolisher?

    func loadIfNeeded(path: String) {
        if polisher == nil { polisher = LlamaPolisher(modelPath: path) }
    }
    var isLoaded: Bool { polisher != nil }

    func rewrite(system: String, text: String) -> String? {
        polisher?.rewrite(system: system, text: text)
    }
}
