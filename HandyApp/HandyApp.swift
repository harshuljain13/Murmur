import SwiftUI
import AVFoundation

@main
struct HandyApp: App {
    @StateObject private var modelManager = ModelManager()
    @StateObject private var transcribeService = TranscribeService.shared
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .environmentObject(transcribeService)
                .environmentObject(router)
                .task { await transcribeService.start(modelManager: modelManager) }
                .onOpenURL { _ in
                    // handy://wake — keyboard asked us to launch so the
                    // background voice service can start. Handled below.
                    startBackgroundServiceIfReady()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // Start the always-on audio service only once setup is complete,
            // and never on the main launch path (it would block the first screen).
            if phase == .active || phase == .background {
                startBackgroundServiceIfReady()
            }
        }
    }

    /// Starts the background dictation service only when it's safe: a model is
    /// downloaded AND microphone permission is granted. No-op otherwise.
    private func startBackgroundServiceIfReady() {
        guard transcribeService.hasModel,
              AVAudioApplication.shared.recordPermission == .granted else { return }
        BackgroundVoiceService.shared.startService(transcribeService: transcribeService)
    }
}

/// Drives full-screen presentation of the recording flow triggered by the keyboard.
final class AppRouter: ObservableObject {
    @Published var showRecording = false
}
