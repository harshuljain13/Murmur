import SwiftUI

@main
struct HandyApp: App {
    @StateObject private var transcribeService = TranscribeService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(transcribeService)
                .task { await transcribeService.start() }
                .onOpenURL { url in
                    if url.scheme == "handy" && url.host == "transcribe" {
                        transcribeService.handleTranscribeURL()
                    }
                }
        }
    }
}
