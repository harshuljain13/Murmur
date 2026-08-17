import SwiftUI

@main
struct HandyApp: App {
    @StateObject private var modelManager = ModelManager()
    @StateObject private var transcribeService = TranscribeService.shared
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .environmentObject(transcribeService)
                .environmentObject(router)
                .task { await transcribeService.start(modelManager: modelManager) }
                .onOpenURL { url in
                    // Keyboard mic → handy://record: pop up the recording screen.
                    // GPU transcription needs the foreground, so recording +
                    // inference happen here, then the keyboard inserts on return.
                    if url.scheme == "handy" && (url.host == "record" || url.host == "wake") {
                        router.showRecording = true
                    }
                }
        }
    }
}

/// Drives full-screen presentation of the recording flow triggered by the keyboard.
final class AppRouter: ObservableObject {
    @Published var showRecording = false
}
