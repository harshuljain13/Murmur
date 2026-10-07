import SwiftUI
import AVFoundation

@main
struct MurmurApp: App {
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
                .onOpenURL { _ in startBackgroundServiceIfReady() }   // murmur://wake
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active || phase == .background { startBackgroundServiceIfReady() }
        }
    }

    /// Start the background dictation service only when a model is downloaded and
    /// mic permission is granted. Keeps the mic warm so the keyboard can trigger
    /// CPU transcription in the background — no app-switch.
    private func startBackgroundServiceIfReady() {
        guard transcribeService.hasModel,
              AVAudioApplication.shared.recordPermission == .granted else { return }
        BackgroundVoiceService.shared.startService(transcribeService: transcribeService)
    }
}

/// Retained for the recording screen (unused in the background flow).
final class AppRouter: ObservableObject {
    @Published var showRecording = false
}
