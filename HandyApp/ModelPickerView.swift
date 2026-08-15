import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var modelManager: ModelManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("choose a model.")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text("downloaded once, runs entirely on your device.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .padding(.horizontal, 28)
                .padding(.top, 56)
                .padding(.bottom, 32)

                // Model list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(ModelVariant.allCases) { variant in
                            ModelCard(variant: variant, manager: modelManager)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

struct ModelCard: View {
    let variant: ModelVariant
    @ObservedObject var manager: ModelManager

    private var downloadState: ModelDownloadState {
        manager.state(for: variant)
    }

    private var isActive: Bool {
        manager.activeModel == variant
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(variant.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        if variant == .parakeetUnified {
                            Text("recommended")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(variant.sizeDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
                actionView
            }

            if case .downloading(let progress) = downloadState {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 4)
                            Capsule()
                                .fill(Color.white)
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 4)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(isActive ? 0.1 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(isActive ? 0.3 : 0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var actionView: some View {
        switch downloadState {
        case .notDownloaded:
            Button {
                Task { await manager.download(variant) }
            } label: {
                Text("Download")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(Capsule())
            }

        case .downloading:
            Button {} label: {
                Text("Downloading")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .disabled(true)

        case .ready:
            if isActive {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Active")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.green)
                }
            } else {
                Button {
                    manager.setActive(variant)
                } label: {
                    Text("Use")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

#Preview {
    ModelPickerView(modelManager: ModelManager())
}
