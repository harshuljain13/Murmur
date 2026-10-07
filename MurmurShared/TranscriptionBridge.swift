import Foundation

/// Result transfer between the (background) MurmurApp and the MurmurKeyboard.
///
/// Uses a shared KEYCHAIN group, not UIPasteboard: iOS blocks a backgrounded
/// app from writing UIPasteboard ("pasteboard not available at this time"),
/// whereas the keychain is reachable from the background and shareable between
/// an app and its extension via the team prefix (no App Group needed).
public final class TranscriptionBridge: @unchecked Sendable {
    public static let shared = TranscriptionBridge()
    private init() {}

    // MARK: - Result (app writes, keyboard reads)

    public func writeResult(_ text: String) {
        KeychainTransfer.write(text, timestamp: Date().timeIntervalSince1970)
    }

    public func readResult(newerThan timestamp: TimeInterval) -> String? {
        latestResult().flatMap { $0.ts > timestamp ? $0.text : nil }
    }

    /// The latest transcript + its timestamp. Survives keyboard-extension
    /// termination (persisted in the keychain).
    public func latestResult() -> (text: String, ts: TimeInterval)? {
        KeychainTransfer.read()
    }

    public func clearResult() {
        KeychainTransfer.clear()
    }

    public var hasActiveModel: Bool {
        UserDefaults.standard.string(forKey: "activeModel") != nil
    }
}
