import Foundation
import UIKit

/// IPC between HandyKeyboard and HandyApp using UIPasteboard.general.
/// UIPasteboard is accessible from both without App Group entitlement,
/// provided the keyboard has Full Access enabled (already required for mic).
///
/// Audio:  keyboard  → pasteboard type "computer.handy.audio"  → main app
/// Result: main app  → pasteboard type "computer.handy.result" → keyboard
public final class TranscriptionBridge: @unchecked Sendable {
    public static let shared = TranscriptionBridge()
    private init() {}

    private let audioType  = "computer.handy.audio"
    private let resultType = "computer.handy.result"
    private let resultTsType = "computer.handy.result.ts"

    private var pb: UIPasteboard { .general }

    // MARK: - Audio (keyboard writes, app reads)

    public func writeAudio(_ data: Data) {
        pb.setData(data, forPasteboardType: audioType)
    }

    public func readAndClearAudio() -> Data? {
        guard let data = pb.data(forPasteboardType: audioType) else { return nil }
        removeItem(type: audioType)
        return data
    }

    // MARK: - Result (app writes, keyboard reads)

    public func writeResult(_ text: String) {
        let ts = String(Date().timeIntervalSince1970)
        pb.setItems([[resultType: text.data(using: .utf8)!,
                      resultTsType: ts.data(using: .utf8)!]])
    }

    public func readResult(newerThan timestamp: TimeInterval) -> String? {
        latestResult().flatMap { $0.ts > timestamp ? $0.text : nil }
    }

    /// The latest transcript on the pasteboard, with its timestamp. Survives
    /// keyboard-extension termination (unlike any in-memory flag).
    public func latestResult() -> (text: String, ts: TimeInterval)? {
        guard let tsData = pb.data(forPasteboardType: resultTsType),
              let ts = Double(String(data: tsData, encoding: .utf8) ?? ""),
              let data = pb.data(forPasteboardType: resultType),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return (text, ts)
    }

    public func clearResult() {
        removeItem(type: resultType)
        removeItem(type: resultTsType)
    }

    public var hasActiveModel: Bool {
        UserDefaults.standard.string(forKey: "activeModel") != nil
    }

    // MARK: - Helpers

    private func removeItem(type: String) {
        pb.items = pb.items.map { item in
            var copy = item; copy.removeValue(forKey: type); return copy
        }.filter { !$0.isEmpty }
    }

    // Unused legacy path kept for when App Group is properly set up later
    public func audioDirURL() -> URL {
        FileManager.default.temporaryDirectory
    }
}
