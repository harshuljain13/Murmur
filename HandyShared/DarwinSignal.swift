import Foundation

/// System-wide cross-process notifications (no App Group / entitlement needed).
/// Lets the keyboard extension signal the main app to start/stop recording
/// while the app runs in the background.
public final class DarwinSignal: @unchecked Sendable {
    public static let shared = DarwinSignal()
    private var handlers: [String: () -> Void] = [:]
    private init() {}

    // Signal names
    public static let recordStart  = "computer.handy.rec.start"
    public static let recordStop   = "computer.handy.rec.stop"
    public static let recordCancel = "computer.handy.rec.cancel" // stop + discard
    public static let resultReady  = "computer.handy.rec.done"
    public static let recordAck    = "computer.handy.rec.ack"   // app → keyboard: "I'm alive & recording"

    public func post(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true
        )
    }

    public func observe(_ name: String, handler: @escaping () -> Void) {
        handlers[name] = handler
        let callback: CFNotificationCallback = { _, _, cfName, _, _ in
            guard let cfName else { return }
            let n = cfName.rawValue as String
            DispatchQueue.main.async { DarwinSignal.shared.handlers[n]?() }
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            callback, name as CFString, nil, .deliverImmediately
        )
    }
}
