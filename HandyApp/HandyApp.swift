import SwiftUI

@main
struct HandyApp: App {
    @StateObject private var modelManager = ModelManager()
    @StateObject private var transcribeService = TranscribeService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .environmentObject(transcribeService)
                .task { await transcribeService.start(modelManager: modelManager) }
                .onOpenURL { url in
                    if url.scheme == "handy" && url.host == "transcribe" {
                        transcribeService.handleTranscribeURL()
                    }
                }
        }
    }
}
