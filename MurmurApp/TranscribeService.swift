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

    var hasModel: Bool { modelManager?.activeModelFileURL() != nil }

    /// Transcribe raw 16 kHz mono float samples (from the background recorder),
    /// publish the result to the pasteboard for the keyboard to insert.
    func transcribeSamples(_ samples: [Float]) async -> String? {
        if await !inference.isLoaded() { await loadEngine() }
        guard await inference.isLoaded() else { return nil }
        do {
            let raw = try await inference.transcribe(samples: samples)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            // Optionally clean the raw dictation into professional text (on-device).
            let text = await PolishService.polish(raw)
            bridge.writeResult(text)
            return text
        } catch {
            return nil
        }
    }

    /// Diagnostic reason surfaced to the UI when transcription yields no text.
    @Published var lastDiagnostic: String = ""

    /// Transcribe a recorded audio file (from the app's own recorder), publish
    /// the text to the pasteboard so the Murmur keyboard can insert it on return.
    /// Returns the transcript (or nil on failure — see `lastDiagnostic`).
    func transcribeRecording(url: URL) async -> String? {
        isTranscribing = true
        defer { isTranscribing = false }

        // Load engine
        if await !inference.isLoaded() {
            guard let modelURL = modelManager?.activeModelFileURL() else {
                lastDiagnostic = "No active model file"
                return nil
            }
            do {
                try await inference.load(modelPath: modelURL.path)
            } catch {
                lastDiagnostic = "Engine load failed: \(error.localizedDescription)"
                return nil
            }
        }
        guard await inference.isLoaded() else {
            lastDiagnostic = "Engine not loaded"
            return nil
        }

        // Read PCM
        let samples: [Float]
        do {
            let file = try AVAudioFile(forReading: url)
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            guard let ch = buffer.floatChannelData?[0] else {
                lastDiagnostic = "Could not read PCM channel"
                return nil
            }
            samples = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
        } catch {
            lastDiagnostic = "Audio read failed: \(error.localizedDescription)"
            return nil
        }

        let peak = samples.map { abs($0) }.max() ?? 0
        let seconds = Double(samples.count) / 16_000.0

        // Run inference
        do {
            let raw = try await inference.transcribe(samples: samples)
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                lastDiagnostic = String(format: "Empty transcript. %d samples (%.1fs), peak %.3f, raw=\"%@\"",
                                        samples.count, seconds, peak, raw)
                return nil
            }
            bridge.writeResult(text) // writes custom markers + plain text in one item
            return text
        } catch {
            lastDiagnostic = String(format: "Inference error: %@ (%d samples, %.1fs, peak %.3f)",
                                    error.localizedDescription, samples.count, seconds, peak)
            return nil
        }
    }

    private func loadEngine() async {
        guard let url = modelManager?.activeModelFileURL() else { return }
        try? await inference.load(modelPath: url.path)
    }
}
