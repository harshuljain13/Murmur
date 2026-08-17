import Foundation

/// Swift wrapper around the transcribe.cpp C API.
public final class TranscribeEngine {

    // transcribe_model and transcribe_session are opaque structs — use OpaquePointer
    private var model: OpaquePointer?
    private var session: OpaquePointer?

    public init(modelPath: String) throws {
        var loadParams = transcribe_model_load_params()
        transcribe_model_load_params_init(&loadParams)
        // CPU (with on-die accelerators, no GPU): works in the background, where
        // the keyboard triggers dictation. iOS blocks GPU/Metal from background,
        // and background GPU (BGContinuedProcessingTask .gpu) is iPad-M3-only.
        loadParams.backend = TRANSCRIBE_BACKEND_CPU_ACCEL

        var modelPtr: OpaquePointer?
        let status = transcribe_model_load_file(modelPath, &loadParams, &modelPtr)
        guard status == TRANSCRIBE_OK, let m = modelPtr else {
            throw TranscribeError.modelLoadFailed(path: modelPath, status: Int(status.rawValue))
        }
        model = m

        var sessionParams = transcribe_session_params()
        transcribe_session_params_init(&sessionParams)
        // Use all cores for CPU inference speed.
        sessionParams.n_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount))

        var sessionPtr: OpaquePointer?
        let sStatus = transcribe_session_init(m, &sessionParams, &sessionPtr)
        guard sStatus == TRANSCRIBE_OK, let s = sessionPtr else {
            transcribe_model_free(m)
            throw TranscribeError.sessionCreateFailed(status: Int(sStatus.rawValue))
        }
        session = s
    }

    deinit {
        if let s = session { transcribe_session_free(s) }
        if let m = model   { transcribe_model_free(m) }
    }

    /// Transcribe 16 kHz mono float32 PCM samples, returns the full transcript.
    public func transcribe(samples: [Float]) throws -> String {
        guard let session else { throw TranscribeError.sessionCreateFailed(status: -1) }

        var runParams = transcribe_run_params()
        transcribe_run_params_init(&runParams)

        let status = samples.withUnsafeBufferPointer { buf in
            transcribe_run(session, buf.baseAddress, Int32(buf.count), &runParams)
        }

        guard status == TRANSCRIBE_OK else {
            throw TranscribeError.transcriptionFailed(status: Int(status.rawValue))
        }

        guard let cStr = transcribe_full_text(session) else { return "" }
        return String(cString: cStr).trimmingCharacters(in: .whitespaces)
    }
}

public enum TranscribeError: LocalizedError {
    case modelLoadFailed(path: String, status: Int)
    case sessionCreateFailed(status: Int)
    case transcriptionFailed(status: Int)

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let p, let s):  return "Model load failed (\(s)) at \(p)"
        case .sessionCreateFailed(let s):     return "Session init failed (\(s))"
        case .transcriptionFailed(let s):     return "Transcription failed (\(s))"
        }
    }
}
