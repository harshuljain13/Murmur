import Foundation

/// Shared IPC contract between HandyKeyboard and HandyApp.
///
/// Flow:
///   Keyboard writes audio → App Group /Audio/pending.wav
///   Keyboard calls openURL(handy://transcribe) → wakes HandyApp
///   HandyApp reads audio, infers, writes result to UserDefaults
///   Keyboard polls UserDefaults["transcriptionResult"] every 300ms
public final class TranscriptionBridge: @unchecked Sendable {
    public static let shared = TranscriptionBridge()

    private let appGroup = "group.computer.handy"
    private let resultKey = "transcriptionResult"
    private let resultTimestampKey = "transcriptionResultTimestamp"

    private init() {}

    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private let audioDataKey = "pendingAudioData"

    // MARK: - Audio transfer (keyboard writes, app reads)
    // Uses UserDefaults instead of a file so no file-path sandbox crossing needed.

    public func writeAudio(_ data: Data) {
        defaults.set(data, forKey: audioDataKey)
    }

    public func readAndClearAudio() -> Data? {
        guard let data = defaults.data(forKey: audioDataKey) else { return nil }
        defaults.removeObject(forKey: audioDataKey)
        return data
    }

    // Kept for legacy callers — returns a temp URL the current process can write to.
    public func audioDirURL() -> URL {
        let dir = containerURL.appendingPathComponent("Audio")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public var pendingAudioURL: URL {
        containerURL.appendingPathComponent("Audio/pending.wav")
    }

    // MARK: - Result (app writes, keyboard reads)

    public func writeResult(_ text: String) {
        defaults.set(text, forKey: resultKey)
        defaults.set(Date().timeIntervalSince1970, forKey: resultTimestampKey)
    }

    public func readResult(newerThan timestamp: TimeInterval) -> String? {
        let ts = defaults.double(forKey: resultTimestampKey)
        guard ts > timestamp, let text = defaults.string(forKey: resultKey) else { return nil }
        return text
    }

    public func clearResult() {
        defaults.removeObject(forKey: resultKey)
        defaults.removeObject(forKey: resultTimestampKey)
    }

    // MARK: - Active model check (keyboard reads to show error state)

    public var hasActiveModel: Bool {
        defaults.string(forKey: "activeModel") != nil
    }
}
