import Foundation

/// Shared contract between HandyApp (inference) and HandyKeyboard (UI).
/// The keyboard extension writes a request; the main app reads it, transcribes,
/// then writes the result back — both sides poll via Darwin notifications.
public struct TranscriptionRequest: Codable {
    public let id: UUID
    public let audioFileURL: URL
    public let requestedAt: Date

    public init(id: UUID = UUID(), audioFileURL: URL) {
        self.id = id
        self.audioFileURL = audioFileURL
        self.requestedAt = Date()
    }
}

public struct TranscriptionResult: Codable {
    public let requestId: UUID
    public let text: String
    public let completedAt: Date

    public init(requestId: UUID, text: String) {
        self.requestId = requestId
        self.text = text
        self.completedAt = Date()
    }
}

public final class TranscriptionBridge {
    public static let shared = TranscriptionBridge()

    private let appGroup = "group.computer.handy"
    private let requestKey = "pendingTranscriptionRequest"
    private let resultKey = "transcriptionResult"
    private let darwinNotificationName = "computer.handy.transcription"

    private init() {}

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    // MARK: - Keyboard side (writes request)

    public func postRequest(_ request: TranscriptionRequest) throws {
        let data = try JSONEncoder().encode(request)
        defaults?.set(data, forKey: requestKey)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinNotificationName as CFString),
            nil, nil, true
        )
    }

    public func readResult(for requestId: UUID) -> TranscriptionResult? {
        guard let data = defaults?.data(forKey: resultKey),
              let result = try? JSONDecoder().decode(TranscriptionResult.self, from: data),
              result.requestId == requestId else { return nil }
        return result
    }

    // MARK: - App side (reads request, writes result)

    public func readPendingRequest() -> TranscriptionRequest? {
        guard let data = defaults?.data(forKey: requestKey) else { return nil }
        return try? JSONDecoder().decode(TranscriptionRequest.self, from: data)
    }

    public func postResult(_ result: TranscriptionResult) throws {
        let data = try JSONEncoder().encode(result)
        defaults?.set(data, forKey: resultKey)
        defaults?.removeObject(forKey: requestKey)
    }

    public func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
}
