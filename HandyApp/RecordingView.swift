import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var transcribeService: TranscribeService
    @EnvironmentObject var router: AppRouter
    @StateObject private var recorder = AppRecorder()

    enum Phase { case recording, transcribing, done, noModel, failed }
    @State private var phase: Phase = .recording
    @State private var resultText = ""

    var body: some View {
        ZStack {
            Handy.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                switch phase {
                case .recording:
                    Text("Listening…")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    WaveBars(levels: recorder.levels)
                        .frame(height: 80)
                        .padding(.horizontal, 40)

                case .transcribing:
                    ProgressView().tint(.white).scaleEffect(1.4)
                    Text("Transcribing…")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.6))

                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52)).foregroundStyle(Handy.pink)
                    Text(resultText)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Text("Swipe back to your app — the text will be inserted.\n(Also copied to clipboard.)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .multilineTextAlignment(.center)

                case .noModel:
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 44)).foregroundStyle(.orange)
                    Text("Download a model first")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Open Handy, pick a Parakeet model, then try again.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .multilineTextAlignment(.center).padding(.horizontal, 32)

                case .failed:
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44)).foregroundStyle(.orange)
                    Text("Didn't catch that")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(transcribeService.lastDiagnostic)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // Action button
                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Handy.pinkDeep)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .opacity(phase == .transcribing ? 0.4 : 1)
                .disabled(phase == .transcribing)
            }
        }
        .onAppear(perform: begin)
    }

    private var primaryTitle: String {
        switch phase {
        case .recording:    return "Done"
        case .transcribing: return "…"
        case .done:         return "Close"
        case .noModel:      return "Close"
        case .failed:       return "Try Again"
        }
    }

    private func primaryAction() {
        switch phase {
        case .recording:
            let url = recorder.stop()
            phase = .transcribing
            Task {
                guard transcribeService.hasModel else { phase = .noModel; return }
                if let text = await transcribeService.transcribeRecording(url: url) {
                    resultText = text
                    phase = .done
                } else {
                    phase = .failed
                }
            }
        case .done, .noModel:
            router.showRecording = false
        case .failed:
            phase = .recording
            begin()
        case .transcribing:
            break
        }
    }

    private func begin() {
        guard transcribeService.hasModel else { phase = .noModel; return }
        phase = .recording
        recorder.start()
    }
}

/// Simple symmetric waveform bars for SwiftUI.
private struct WaveBars: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Handy.pink)
                        .frame(width: 4, height: max(4, level * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
