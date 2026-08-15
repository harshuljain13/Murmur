import SwiftUI

struct ContentView: View {
    @StateObject private var modelManager = ModelManager()
    @State private var showModelPicker = false

    var body: some View {
        if showModelPicker {
            ModelPickerView(modelManager: modelManager)
                .transition(.move(edge: .trailing))
        } else {
            LandingView {
                withAnimation(.easeInOut(duration: 0.35)) {
                    showModelPicker = true
                }
            }
            .transition(.move(edge: .leading))
        }
    }
}

#Preview {
    ContentView()
}
