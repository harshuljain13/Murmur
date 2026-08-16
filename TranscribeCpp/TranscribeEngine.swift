import Foundation

/// Swift wrapper around the transcribe.cpp C API.
public final class TranscribeEngine {

    private var model: UnsafeMutablePointer<transcribe_model>?
    private var session: UnsafeMutablePointer<transcribe_session>?

    public init(modelPath: String) throws {
        var loadParams = transcribe_model_load_params()
        transcribe_model_load_params_init(&loadParams)

        let status = transcribe_model_load_file(modelPath, &loadParams, &model)
        guard status == TRANSCRIBE_OK, model != nil else {
            throw TranscribeError.modelLoadFailed(path: modelPath, status: Int(status.rawValue))
        }

        var sessionParams = transcribe_session_params()
        transcribe_session_params_init(&sessionParams)

        let sStatus = transcribe_session_init(model, &sessionParams, &session)
        guard sStatus == TRANSCRIBE_OK, session != nil else {
            transcribe_model_free(model)
            throw TranscribeError.sessionCreateFailed(status: Int(sStatus.rawValue))
        }
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
