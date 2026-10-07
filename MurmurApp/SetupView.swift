import SwiftUI
import AVFoundation

struct SetupView: View {
    @State private var micGranted = AVAudioApplication.shared.recordPermission == .granted
    @State private var polishOn = PolishService.isEnabled
    @StateObject private var polishModel = PolishModelManager()
    @ObservedObject private var diag = VoiceDiagnostics.shared
    var onBack: () -> Void = {}

    var body: some View {
        ZStack {
            Murmur.background.ignoresSafeArea()

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
                    Text("enable the murmur keyboard in iOS Settings.")
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
                    StepRow(number: "3", text: "Tap **Add New Keyboard** → select **Murmur**")
                    StepRow(number: "4", text: "Tap **Murmur** again → turn on **Allow Full Access**")
                }
                .padding(.horizontal, 24)

                // Polish toggle — on-device open-source LLM (Qwen 0.5B)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $polishOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("✨ Polish my dictation")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Murmur.cream)
                            Text("Clean filler & grammar into professional text — on-device, open-source (Qwen 0.5B).")
                                .font(.system(size: 12))
                                .foregroundStyle(Murmur.text(0.5))
                        }
                    }
                    .tint(Murmur.accentDeep)
                    .onChange(of: polishOn) { _, v in
                        PolishService.isEnabled = v
                        if v && polishModel.state != .ready { Task { await polishModel.download() } }
                    }

                    switch polishModel.state {
                    case .downloading(let p):
                        ProgressView(value: p).tint(Murmur.accent)
                        Text("Downloading model… \(Int(p * 100))%")
                            .font(.system(size: 12)).foregroundStyle(Murmur.text(0.5))
                    case .ready:
                        Text("Model ready ✓").font(.system(size: 12)).foregroundStyle(Murmur.accent)
                    case .notDownloaded:
                        if polishOn {
                            Text("Needs a one-time ~469 MB download.")
                                .font(.system(size: 12)).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(14)
                .background(Murmur.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .onAppear { polishModel.refresh() }

                // Diagnostics + self-test
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(diag.keepAlive ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(diag.keepAlive ? "Background service running" : "Background service off")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Murmur.text(0.7))
                        Spacer()
                        Button("Test Mic") { runMicTest() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Murmur.accent)
                    }
                    Text("Mic permission: \(micPermissionString)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(micGranted ? Murmur.text(0.5) : .orange)
                    Text("Status: \(diag.status)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Murmur.text(0.5))
                    if !diag.lastTranscript.isEmpty {
                        Text("Heard: \(diag.lastTranscript)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Murmur.accent)
                    }
                    if !diag.lastError.isEmpty {
                        Text(diag.lastError)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Murmur.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.top, 16)

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
                            .background(Murmur.accentDeep)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Text("After enabling, open any app (e.g. WhatsApp), tap a text field, switch to Murmur keyboard, and tap the mic.")
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

    private var micPermissionString: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return "granted ✓"
        case .denied: return "DENIED — Open Settings → Microphone"
        case .undetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }

    /// Ensures permission first, then runs the foreground capture test.
    private func runMicTest() {
        VoiceDiagnostics.shared.lastTranscript = ""
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            BackgroundVoiceService.shared.testCapture()
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    micGranted = granted
                    if granted { BackgroundVoiceService.shared.testCapture() }
                    else { VoiceDiagnostics.shared.status = "mic denied" }
                }
            }
        case .denied:
            VoiceDiagnostics.shared.status = "mic DENIED — Open Settings"
        @unknown default:
            break
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
                .background(Murmur.accentDeep)
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
