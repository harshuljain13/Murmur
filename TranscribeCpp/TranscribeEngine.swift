import Foundation

/// Wraps the transcribe.cpp C API for use from Swift.
/// One instance per loaded model — load once, transcribe many times.
public final class TranscribeEngine {

    private var model: OpaquePointer?
    private var session: OpaquePointer?

    public init(modelPath: String) throws {
        var params = transcribe_model_params_init()
        params.n_threads = Int32(ProcessInfo.processInfo.activeProcessorCount)
        params.use_metal = true

        model = transcribe_model_load(modelPath, &params)
        guard model != nil else {
            throw TranscribeError.modelLoadFailed(path: modelPath)
        }

        var sessionParams = transcribe_session_params_init()
        session = transcribe_session_create(model, &sessionParams)
        guard session != nil else {
            throw TranscribeError.sessionCreateFailed
        }
    }

    deinit {
        if let s = session { transcribe_session_free(s) }
        if let m = model  { transcribe_model_free(m)   }
    }

    /// Transcribe 16 kHz mono PCM samples, returns the transcript string.
    public func transcribe(samples: [Float]) throws -> String {
        guard let session else { throw TranscribeError.sessionCreateFailed }

        var runParams = transcribe_run_params_init()
        let result = samples.withUnsafeBufferPointer { buf in
            transcribe_run(session, buf.baseAddress, Int32(buf.count), &runParams)
        }
        guard let result else { throw TranscribeError.transcriptionFailed }
        defer { transcribe_result_free(result) }

        guard let cStr = transcribe_result_text(result) else { return "" }
        return String(cString: cStr).trimmingCharacters(in: .whitespaces)
    }
}

public enum TranscribeError: LocalizedError {
    case modelLoadFailed(path: String)
    case sessionCreateFailed
    case transcriptionFailed

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let p): return "Failed to load model at \(p)"
        case .sessionCreateFailed:    return "Failed to create transcription session"
        case .transcriptionFailed:    return "Transcription returned no result"
        }
    }
}
