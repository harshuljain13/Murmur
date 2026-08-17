import SwiftUI
import AVFoundation

struct SetupView: View {
    @State private var micGranted = AVAudioApplication.shared.recordPermission == .granted
    var onBack: () -> Void = {}

    var body: some View {
        ZStack {
            Handy.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("one last step.")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text("enable the handy keyboard in iOS Settings.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 40)

                VStack(spacing: 12) {
                    Button(action: requestMic) {
                        StepRow(
                            number: micGranted ? "✓" : "1",
                            text: micGranted
                                ? "**Microphone enabled** ✓"
                                : "**Tap here to allow the microphone** (required — the keyboard can only record after the app is granted mic access)",
                            highlight: !micGranted
                        )
                    }
                    .buttonStyle(.plain)
                    StepRow(number: "2", text: "Open **Settings → General → Keyboard → Keyboards**")
                    StepRow(number: "3", text: "Tap **Add New Keyboard** → select **Handy**")
                    StepRow(number: "4", text: "Tap **Handy** again → turn on **Allow Full Access**")
                }
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        openAppSettings()
                    } label: {
                        Text("Open Settings")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Handy.pinkDeep)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Text("After enabling, open any app (e.g. WhatsApp), tap a text field, switch to Handy keyboard, and tap the mic.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            // Prompt for mic on first view so the keyboard can later record.
            if AVAudioApplication.shared.recordPermission == .undetermined {
                requestMic()
            }
        }
    }

    private func requestMic() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { micGranted = granted }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

private struct StepRow: View {
    let number: String
    let text: String
    var highlight: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Handy.pinkDeep)
                .clipShape(Circle())

            Text(.init(text))
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(16)
        .background(highlight ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(highlight ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    SetupView()
}
