import Foundation

/// Rewrites raw dictation into clean, professional text using an on-device,
/// open-source LLM (Qwen2.5-0.5B-Instruct via llama.cpp). We control the system
/// prompt, so it only re-words — it never adds content or answers questions.
/// Runs on CPU (background-safe). Falls back to the raw transcript on any error.
enum PolishService {

    // Model
    static let modelURL = URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf")!
    static let modelFilename = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
    static let modelExpectedBytes: Int64 = 491_400_032

    private static let enabledKey = "handy.polishEnabled"
    private static let engine = LlamaEngine()

    private static let systemPrompt = """
    You are a text-cleanup tool for voice dictation. Rewrite the user's message \
    to fix grammar, spelling, punctuation and capitalization, and to remove filler \
    words like "um", "uh", "you know", and repeated "like". Keep the original \
    meaning, wording and tone as much as possible. Do NOT add new information, do \
    NOT answer questions, do NOT explain, do NOT add greetings or sign-offs. \
    Output ONLY the cleaned-up text.
    """

    // MARK: - Toggle

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    // MARK: - Model file

    static var modelPath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models/\(modelFilename)")
    }

    static var isModelDownloaded: Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: modelPath.path)[.size] as? Int64 else { return false }
        return size >= Int64(Double(modelExpectedBytes) * 0.99)
    }

    // MARK: - Polish

    static func polish(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, isModelDownloaded, !trimmed.isEmpty else { return text }

        await engine.loadIfNeeded(path: modelPath.path)
        guard await engine.isLoaded else { return text }

        let cleaned = await engine.rewrite(system: systemPrompt, text: trimmed)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleaned, !cleaned.isEmpty { return cleaned }
        return text
    }
}
