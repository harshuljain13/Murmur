import SwiftUI

enum AppScreen: String {
    case landing, modelPicker, setup
}

struct ContentView: View {
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var router: AppRouter
    @State private var screen: AppScreen = .landing
    @State private var restored = false

    var body: some View {
        Group {
            switch screen {
            case .landing:
                LandingView {
                    withAnimation(.easeInOut(duration: 0.35)) { screen = .modelPicker }
                }
                .transition(.move(edge: .leading))

            case .modelPicker:
                ModelPickerView(
                    onBack: { withAnimation(.easeInOut(duration: 0.3)) { screen = .landing } },
                    onContinue: { withAnimation(.easeInOut(duration: 0.3)) { screen = .setup } }
                )
                .transition(.move(edge: .trailing))

            case .setup:
                SetupView(
                    onBack: { withAnimation(.easeInOut(duration: 0.3)) { screen = .modelPicker } }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .fullScreenCover(isPresented: $router.showRecording) { RecordingView() }
        .onAppear {
            // Restore the last screen once so resuming/relaunching doesn't dump
            // the user back on the Landing page.
            guard !restored else { return }
            restored = true
            if let saved = UserDefaults.standard.string(forKey: "murmur.lastScreen"),
               let s = AppScreen(rawValue: saved) {
                screen = s
            } else if modelManager.activeModel != nil {
                screen = .setup    // already configured → go to the main screen
            }
        }
        .onChange(of: screen) { _, s in
            UserDefaults.standard.set(s.rawValue, forKey: "murmur.lastScreen")
        }
    }
}

#Preview {
    ContentView().environmentObject(ModelManager())
}
