import Foundation

/// Shared IPC contract between HandyKeyboard and HandyApp.
///
/// Flow:
///   Keyboard writes audio → App Group /Audio/pending.wav
///   Keyboard calls openURL(handy://transcribe) → wakes HandyApp
///   HandyApp reads audio, infers, writes result to UserDefaults
///   Keyboard polls UserDefaults["transcriptionResult"] every 300ms
public final class TranscriptionBridge {
    public static let shared = TranscriptionBridge()

    private let appGroup = "group.computer.handy"
    private let resultKey = "transcriptionResult"
    private let resultTimestampKey = "transcriptionResultTimestamp"

    private init() {}

    private var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    // MARK: - Audio file (keyboard writes, app reads)

    public var pendingAudioURL: (() -> URL?) = {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.computer.handy") else { return nil }
        return base.appendingPathComponent("Audio/pending.wav")
    }

    public func audioDirURL() -> URL? {
        guard let base = containerURL else { return nil }
        let dir = base.appendingPathComponent("Audio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Result (app writes, keyboard reads)

    public func writeResult(_ text: String) {
        defaults?.set(text, forKey: resultKey)
        defaults?.set(Date().timeIntervalSince1970, forKey: resultTimestampKey)
    }

    public func readResult(newerThan timestamp: TimeInterval) -> String? {
        guard let ts = defaults?.double(forKey: resultTimestampKey), ts > timestamp,
              let text = defaults?.string(forKey: resultKey) else { return nil }
        return text
    }

    public func clearResult() {
        defaults?.removeObject(forKey: resultKey)
        defaults?.removeObject(forKey: resultTimestampKey)
    }

    // MARK: - Active model check (keyboard reads to show error state)

    public var hasActiveModel: Bool {
        defaults?.string(forKey: "activeModel") != nil
    }
}
