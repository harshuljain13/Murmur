import SwiftUI

struct ContentView: View {
    @StateObject private var modelManager = ModelManager()

    var body: some View {
        NavigationStack {
            List {
                Section("Models") {
                    ForEach(ModelVariant.allCases) { variant in
                        ModelRow(variant: variant, manager: modelManager)
                    }
                }

                Section("Setup") {
                    SetupInstructionsView()
                }
            }
            .navigationTitle("Handy")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await modelManager.loadState()
        }
    }
}

struct ModelRow: View {
    let variant: ModelVariant
    @ObservedObject var manager: ModelManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(variant.displayName)
                    .font(.body)
                Text(variant.sizeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch manager.state(for: variant) {
            case .notDownloaded:
                Button("Download") {
                    Task { await manager.download(variant) }
                }
                .buttonStyle(.bordered)
            case .downloading(let progress):
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .ready:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if manager.activeModel == variant {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button("Use") {
                            manager.setActive(variant)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct SetupInstructionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Enable Handy Keyboard", systemImage: "keyboard")
                .font(.headline)

            Text("1. Open **Settings → General → Keyboard → Keyboards**")
            Text("2. Tap **Add New Keyboard** and select **Handy**")
            Text("3. Tap **Handy** and enable **Allow Full Access**")
                .foregroundStyle(.orange)
            Text("Full Access is required for microphone access inside the keyboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
