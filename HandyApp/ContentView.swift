import SwiftUI

enum AppScreen {
    case landing, modelPicker, setup
}

struct ContentView: View {
    @EnvironmentObject private var modelManager: ModelManager
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
                ModelPickerView()
                    .transition(.move(edge: .trailing))

            case .setup:
                SetupView()
                    .transition(.move(edge: .trailing))
            }
        }
        .onAppear {
            // If model already downloaded from a previous launch, skip to setup
            if modelManager.activeModel != nil {
                screen = .setup
            }
        }
        .onChange(of: modelManager.activeModel) { _, newValue in
            if newValue != nil && screen == .modelPicker {
                withAnimation(.easeInOut(duration: 0.35)) {
                    screen = .setup
                }
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(ModelManager())
}
