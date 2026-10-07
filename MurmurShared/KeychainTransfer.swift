import Foundation
import Security

/// Shares the transcript from the (background) app to the keyboard extension via
/// a shared keychain access group. Unlike UIPasteboard, the keychain is
/// accessible from a backgrounded app; unlike App Groups, a keychain access
/// group is auto-provisioned from the team prefix (no paid capability needed).
public enum KeychainTransfer {
    // Must match the group declared in both targets' entitlements. The team
    // prefix (AppIdentifierPrefix) for this project is ML63WLS943.
    private static let accessGroup = "ML63WLS943.app.murmur.shared"
    private static let service = "app.murmur.transcript"
    private static let account = "latest"

    /// App side: store transcript + timestamp.
    public static func write(_ text: String, timestamp: TimeInterval) {
        let payload = "\(timestamp)\n\(text)"
        guard let data = payload.data(using: .utf8) else { return }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Keyboard side: read transcript + timestamp (nil if none).
    public static func read() -> (text: String, ts: TimeInterval)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let payload = String(data: data, encoding: .utf8) else { return nil }

        let parts = payload.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let ts = TimeInterval(parts[0]) else { return nil }
        return (String(parts[1]), ts)
    }

    public static func clear() {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(base as CFDictionary)
    }
}
