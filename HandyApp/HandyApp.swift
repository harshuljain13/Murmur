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
                    // handy://record — launched by the keyboard's mic button.
                    if url.scheme == "handy" && url.host == "record" {
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
