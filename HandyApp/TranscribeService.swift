import Foundation
import AVFoundation

/// Background actor that owns the TranscribeEngine.
/// Ensures inference never runs on the main actor and never crosses sendability boundaries.
private actor InferenceActor {
    private var engine: TranscribeEngine?

    func load(modelPath: String) throws {
        engine = try TranscribeEngine(modelPath: modelPath)
    }

    func isLoaded() -> Bool { engine != nil }

    func transcribe(samples: [Float]) throws -> String {
        guard let engine else { throw TranscribeError.sessionCreateFailed(status: -1) }
        return try engine.transcribe(samples: samples)
    }
}

/// Main-actor service wired into HandyApp. Handles handy://transcribe URL,
/// runs Parakeet inference via InferenceActor, writes result to App Group.
@MainActor
final class TranscribeService: ObservableObject {
    static let shared = TranscribeService()

    @Published var isTranscribing = false

    private let inference = InferenceActor()
    private let bridge = TranscriptionBridge.shared
    private let modelManager = ModelManager()

    private init() {}

    func start() async {
        await modelManager.loadState()
        await loadEngine()
    }

    func handleTranscribeURL() {
        Task { await runTranscription() }
    }

    private func loadEngine() async {
        guard let url = modelManager.activeModelFileURL() else { return }
        try? await inference.load(modelPath: url.path)
    }

    private func runTranscription() async {
        guard let audioURL = bridge.pendingAudioURL(),
              FileManager.default.fileExists(atPath: audioURL.path) else {
            bridge.writeResult("ERROR: no audio file found")
            return
        }

        isTranscribing = true
        defer { isTranscribing = false }

        if await !inference.isLoaded() { await loadEngine() }

        do {
            let samples = try loadPCM(from: audioURL)
            let text = try await inference.transcribe(samples: samples)
            bridge.writeResult(text.isEmpty ? "…" : text)
        } catch {
            bridge.writeResult("ERROR: \(error.localizedDescription)")
        }

        try? FileManager.default.removeItem(at: audioURL)
    }

    private func loadPCM(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000, channels: 1, interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }
}
