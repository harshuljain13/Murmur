import Foundation
import AVFoundation
import UIKit

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

@MainActor
final class TranscribeService: ObservableObject {
    static let shared = TranscribeService()

    @Published var isTranscribing = false

    private let inference = InferenceActor()
    private let bridge = TranscriptionBridge.shared
    private var modelManager: ModelManager?

    private init() {}

    func start(modelManager: ModelManager) async {
        self.modelManager = modelManager
        await modelManager.loadState()
        await loadEngine()
    }

    func handleTranscribeURL() {
        Task { await runTranscription() }
    }

    var hasModel: Bool { modelManager?.activeModelFileURL() != nil }

    /// Transcribe a recorded audio file (from the app's own recorder), publish
    /// the text to the pasteboard so the Handy keyboard can insert it on return.
    /// Returns the transcript (or nil on failure).
    func transcribeRecording(url: URL) async -> String? {
        isTranscribing = true
        defer { isTranscribing = false }

        if await !inference.isLoaded() { await loadEngine() }
        guard await inference.isLoaded() else { return nil }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            guard let ch = buffer.floatChannelData?[0] else { return nil }
            let samples = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))

            let text = try await inference.transcribe(samples: samples)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            bridge.writeResult(text)          // for the keyboard to insert
            UIPasteboard.general.string = text // fallback: user can paste manually
            return text
        } catch {
            return nil
        }
    }

    private func loadEngine() async {
        guard let url = modelManager?.activeModelFileURL() else { return }
        try? await inference.load(modelPath: url.path)
    }

    private func runTranscription() async {
        guard let audioData = bridge.readAndClearAudio() else {
            bridge.writeResult("ERROR: no audio data found")
            return
        }

        isTranscribing = true
        defer { isTranscribing = false }

        if await !inference.isLoaded() { await loadEngine() }

        do {
            let samples = try loadPCM(from: audioData)
            let text = try await inference.transcribe(samples: samples)
            bridge.writeResult(text.isEmpty ? "…" : text)
        } catch {
            bridge.writeResult("ERROR: \(error.localizedDescription)")
        }
    }

    private func loadPCM(from data: Data) throws -> [Float] {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("handy_audio.wav")
        try data.write(to: tmp)
        let file = try AVAudioFile(forReading: tmp)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000, channels: 1, interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }
}
