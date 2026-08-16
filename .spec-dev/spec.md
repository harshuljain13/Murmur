# Spec: handy-ios

Status: Draft
Last updated: 2026-08-16

## Summary
handy-ios is a two-target iOS app (main app + custom keyboard extension) that
runs Parakeet GGUF speech-to-text inference on-device via transcribe.cpp
(Metal-accelerated). The keyboard extension captures audio and delegates
inference to the main app via an App Group shared container + Darwin
notifications. Transcribed text is inserted directly into the active text field.

---

## Design Decisions

### Decision 1: Inference runtime
**Options considered**: ONNX Runtime (Parakeet V2/V3 tar.gz), WhisperKit (Whisper only), transcribe.cpp GGUF
**Chosen**: transcribe.cpp GGUF
**Why**: Same library and model format as the desktop Handy app. Clean C API,
Metal backend, ggml runtime that already runs on Apple Silicon. Parakeet Unified
GGUF is the recommended model per handy.computer. ONNX would require a separate
model format and heavier runtime; WhisperKit is Whisper-only.

### Decision 2: Where inference runs
**Options considered**: Inside keyboard extension, inside main app, dedicated network service
**Chosen**: Main app process
**Why**: Keyboard extensions have a hard ~50 MB memory limit. Parakeet Q4 needs
~500 MB+ RAM during inference. The main app has no such cap. Inference stays
local (no network service needed).

### Decision 3: IPC mechanism between keyboard and main app
**Options considered**: Darwin notifications + UserDefaults (App Group), NSXPCConnection, openURL
**Chosen**: App Group shared files + openURL wakeup
**Why**: Darwin notifications from a keyboard extension cannot reliably wake a
suspended main app. `openURL` with a custom scheme (`handy://transcribe`) forces
iOS to bring the main app to foreground or wake it in background. Audio file
written to App Group container; result written back; keyboard polls UserDefaults
for the result. Simple, no entitlement beyond App Group.
**Trade-off**: User sees the main app briefly come forward on first transcription
if it was killed. Acceptable for v1; background processing entitlement is a v2
improvement.

### Decision 4: Models offered in v1
**Options considered**: All 5 Whisper + all Parakeet variants, Parakeet only, single model
**Chosen**: Two Parakeet Unified variants (Q4_K_M and Q8_0)
**Why**: Gives users a meaningful size vs. quality choice without overwhelming
them. Nemotron multilingual deferred to v2.

### Decision 5: UI design language
**Options considered**: Apple HIG default, custom brand, match handy.computer
**Chosen**: Match handy.computer aesthetic
**Why**: Consistency with the desktop app — dark background, bold lowercase
hero text, minimal flourish, developer-first feel.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   HandyApp                       │
│  ┌────────────┐   ┌───────────────────────────┐ │
│  │ LandingView│   │ TranscribeService          │ │
│  │ + Model    │   │  - loads TranscribeEngine  │ │
│  │   Picker   │   │  - watches App Group for   │ │
│  └────────────┘   │    pending audio file      │ │
│                   │  - writes result back      │ │
│  ModelManager     └───────────────────────────┘ │
│  - downloads GGUF to App Group /Models/          │
│  - tracks active model in UserDefaults           │
└──────────────────────┬──────────────────────────┘
                       │ App Group: group.computer.handy
                       │ (shared files + UserDefaults)
┌──────────────────────┴──────────────────────────┐
│               HandyKeyboard                      │
│  KeyboardViewController                          │
│  - mic button (tap to record / tap to stop)      │
│  - AudioRecorder: 16 kHz mono PCM → WAV file     │
│  - writes WAV to App Group /pending_audio.wav    │
│  - calls openURL(handy://transcribe) to wake app │
│  - polls UserDefaults every 300 ms for result    │
│  - inserts result via textDocumentProxy          │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  transcribe.cpp (static lib, arm64 + Metal)      │
│  TranscribeEngine.swift wraps C API:             │
│    transcribe_model_load → transcribe_run →      │
│    transcribe_result_text                        │
└─────────────────────────────────────────────────┘
```

## File Layout (within Xcode project)

```
handy-ios/
├── HandyApp/
│   ├── HandyApp.swift          # @main, registers handy:// URL scheme
│   ├── ContentView.swift       # Landing ↔ ModelPicker router
│   ├── LandingView.swift       # Hero + Get Started CTA
│   ├── ModelPickerView.swift   # Model cards + download progress
│   └── TranscribeService.swift # Background watcher + inference caller
├── HandyKeyboard/
│   └── KeyboardViewController.swift  # Custom keyboard UI + IPC
├── HandyShared/
│   ├── ModelVariant.swift      # Enum: Q4_K_M, Q8_0 + URLs
│   ├── ModelManager.swift      # Download, state, active model
│   ├── AudioRecorder.swift     # AVAudioEngine → [Float] samples
│   └── TranscriptionBridge.swift # App Group paths + UserDefaults keys
├── TranscribeCpp/
│   ├── TranscribeEngine.swift  # Swift ↔ C API wrapper
│   └── transcribe_bridge.h    # ObjC bridging header (stubs until lib built)
├── transcribe.cpp/             # git submodule
├── scripts/
│   └── build_transcribe_ios.sh # Cross-compile libtranscribe.a for iOS
└── project.yml                 # xcodegen spec
```

## IPC Flow (keyboard → app → keyboard)

```
1. User taps mic in HandyKeyboard
2. AudioRecorder records 16 kHz mono PCM
3. User taps stop → WAV written to App Group /Audio/pending.wav
4. KeyboardViewController calls UIApplication.shared.open(URL("handy://transcribe"))
5. iOS wakes / foregrounds HandyApp
6. HandyApp.swift handles URL → TranscribeService.handleTranscribeRequest()
7. TranscribeService reads /Audio/pending.wav → [Float] samples
8. TranscribeEngine.transcribe(samples:) → String  (Metal inference)
9. Result written to UserDefaults(suiteName: appGroup)["transcriptionResult"]
10. KeyboardViewController poll fires → reads result → textDocumentProxy.insertText()
11. UserDefaults result key cleared
```

## Edge Cases and Error Handling

- **No model downloaded**: keyboard shows "Open Handy app to download a model"
  with a button that calls openURL to the main app
- **Main app killed / not responding**: keyboard poll times out after 30 s,
  shows "Transcription timed out — open Handy app"
- **Audio permission denied**: keyboard shows inline permission prompt directing
  user to Settings; requires Full Access to be enabled
- **Model load failure** (corrupt file): TranscribeEngine throws, TranscribeService
  catches, writes error string to result key so keyboard surfaces it
- **Concurrent transcription requests**: TranscribeService serialises via an actor;
  second request waits for first to finish

## What's Explicitly Not in v1
- Whisper models
- Nemotron / multilingual
- Streaming transcription
- LLM post-processing
- Transcript history / search
- Background processing entitlement (app comes to foreground on transcribe)
- iPad split-screen keyboard layout

## Dependencies
- `handy-computer/transcribe.cpp` (submodule) — C++ inference, MIT licence
- `ggml` (bundled inside transcribe.cpp) — tensor backend
- No Swift Package dependencies — stdlib + AVFoundation + UIKit only

## Open Questions (resolved)
- *Does transcribe.cpp cross-compile to iOS?* → To be confirmed by running
  `scripts/build_transcribe_ios.sh`; CMakeLists already has Metal + arm64 paths.
- *Darwin notifications from keyboard extension?* → Resolved: use `openURL`
  with custom URL scheme instead; more reliable for waking suspended app.
- *Parakeet Q4 RAM requirement?* → ~500 MB peak during inference; iPhone 14
  (6 GB RAM) handles it comfortably; iPhone 12/13 (4 GB) may be tight at Q8.
