import Foundation
import AVFoundation

/// Runs in the main app process. Watches for a pending audio file written
/// by the keyboard extension, runs Parakeet inference, writes the result
/// back to the shared App Group UserDefaults.
@MainActor
final class TranscribeService: ObservableObject {
    static let shared = TranscribeService()

    @Published var isTranscribing = false
    @Published var lastError: String?

    private var engine: TranscribeEngine?
    private let bridge = TranscriptionBridge.shared
    private let modelManager = ModelManager()

    private init() {}

    func start() async {
        await modelManager.loadState()
        await loadEngine()
    }

    // Called when the app receives handy://transcribe
    func handleTranscribeURL() {
        Task { await runTranscription() }
    }

    private func loadEngine() async {
        guard let url = modelManager.activeModelFileURL() else { return }
        do {
            engine = try TranscribeEngine(modelPath: url.path)
        } catch {
            lastError = "Model load failed: \(error.localizedDescription)"
        }
    }

    private func runTranscription() async {
        guard let audioURL = bridge.pendingAudioURL(), FileManager.default.fileExists(atPath: audioURL.path) else {
            bridge.writeResult("ERROR: no audio file found")
            return
        }

        isTranscribing = true
        defer { isTranscribing = false }

        // Reload engine if model changed
        if engine == nil { await loadEngine() }

        guard let engine else {
            bridge.writeResult("ERROR: no model loaded — open Handy to download a model")
            return
        }

        do {
            let samples = try loadPCM(from: audioURL)
            let text = try await Task.detached(priority: .userInitiated) {
                try engine.transcribe(samples: samples)
            }.value
            bridge.writeResult(text.isEmpty ? "…" : text)
        } catch {
            bridge.writeResult("ERROR: \(error.localizedDescription)")
        }

        try? FileManager.default.removeItem(at: audioURL)
    }

    private func loadPCM(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let frameCount = AVAudioFrameCount(file.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }
}
