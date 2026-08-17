import SwiftUI

enum AppScreen {
    case landing, modelPicker, setup
}

struct ContentView: View {
    @EnvironmentObject private var modelManager: ModelManager
    @EnvironmentObject private var router: AppRouter
    @State private var screen: AppScreen = .landing

    var body: some View {
        Group {
            switch screen {
            case .landing:
                LandingView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        screen = .modelPicker
                    }
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
        .fullScreenCover(isPresented: $router.showRecording) {
            RecordingView()
        }
    }
}

#Preview {
    ContentView().environmentObject(ModelManager())
}
