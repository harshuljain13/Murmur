import Foundation
import Combine

/// Observable status of the background voice service, shown in-app so we can
/// see what's happening (the service runs even when the app is backgrounded).
/// Not @MainActor: `set(...)` may be called from the audio queue and hops to
/// main to publish. Direct property writes must be done on the main thread.
final class VoiceDiagnostics: ObservableObject, @unchecked Sendable {
    static let shared = VoiceDiagnostics()
    @Published var keepAlive = false
    @Published var status = "idle"
    @Published var lastError = ""
    @Published var lastTranscript = ""
    private init() {}

    func set(status: String? = nil, keepAlive: Bool? = nil,
             error: String? = nil, transcript: String? = nil) {
        DispatchQueue.main.async {
            if let status { self.status = status }
            if let keepAlive { self.keepAlive = keepAlive }
            if let error { self.lastError = error }
            if let transcript { self.lastTranscript = transcript }
        }
    }
}
