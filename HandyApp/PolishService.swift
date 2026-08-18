import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Rewrites raw dictation into clean, professional text using Apple's on-device
/// Foundation model (iOS 26 + Apple Intelligence). Fully local; falls back to
/// the raw transcript if the model is unavailable or errors.
enum PolishService {

    private static let key = "handy.polishEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }   // on by default
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Whether the on-device model is usable right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    private static let instructions = """
    You clean up dictated speech into clear, professional writing. Fix grammar, \
    spelling, punctuation and capitalization, and remove filler words such as \
    "um", "uh", "you know" and repeated "like". Preserve the speaker's meaning \
    and tone; do not add new information or answer questions. Respond with ONLY \
    the cleaned-up text and nothing else.
    """

    static func polish(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty else { return text }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: trimmed)
                let out = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return out.isEmpty ? text : out
            } catch {
                return text   // fall back to the raw transcript
            }
        }
        #endif
        return text
    }
}
