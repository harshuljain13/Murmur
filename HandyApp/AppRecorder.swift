import Foundation
import AVFoundation

/// Records mic audio in the MAIN APP (where iOS permits microphone access).
/// Publishes a rolling window of levels for the waveform.
@MainActor
final class AppRecorder: ObservableObject {
    @Published var levels: [CGFloat] = []
    @Published var isRecording = false

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private let maxBars = 48

    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("handy_app_rec.wav")

    func start() {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let rec = try AVAudioRecorder(url: fileURL, settings: settings)
            rec.isMeteringEnabled = true
            rec.record()
            recorder = rec
            isRecording = true
            levels = []

            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sample() }
            }
        } catch {
            isRecording = false
        }
    }

    private func sample() {
        guard let rec = recorder else { return }
        rec.updateMeters()
        let power = rec.averagePower(forChannel: 0)
        let normalized = pow(10, power / 40)
        levels.append(CGFloat(min(1, max(0.03, normalized))))
        if levels.count > maxBars { levels.removeFirst(levels.count - maxBars) }
    }

    /// Stops recording and returns the recorded file URL.
    @discardableResult
    func stop() -> URL {
        meterTimer?.invalidate(); meterTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        return fileURL
    }
}
