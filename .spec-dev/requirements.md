# Requirements: murmur-ios

## Problem Statement
There is no iOS equivalent of Handy (handy.computer) — a free, offline,
open-source speech-to-text tool. iPhone users who want private, on-device
dictation in any app must either use Apple's Siri-based keyboard (cloud) or
pay for WhisperFlow. There is no open-source, Parakeet-powered alternative.

## Goals
- Ship an iOS custom keyboard that lets users dictate into any text field
  by tapping a mic button, with transcription running entirely on-device
- Use Parakeet GGUF models (via handy-computer/transcribe.cpp) as the
  inference engine — same model family as the desktop Handy app
- Zero network calls during transcription — audio never leaves the device
- Users can choose and download their preferred Parakeet model variant
  (trade off size vs. quality)

## Non-Goals (explicitly out of scope for v1)
- Whisper model support (Parakeet only)
- Streaming / real-time word-by-word preview
- Multi-language support (English only for v1; Nemotron multilingual is a v2 concern)
- Post-processing with an LLM (e.g. grammar fix, formatting)
- Apple Watch or macOS companion app
- iCloud sync of transcription history
- Server-side fallback when model is not downloaded

## Success Criteria
- User can open the app, download a Parakeet model, enable the keyboard in
  iOS Settings, and dictate text into any third-party app within 5 minutes
- Transcription latency ≤ 3 seconds for a 10-second utterance on iPhone 14+
- App passes App Store review (mic permission, Full Access disclosure, no crashes)
- Cold-start of inference engine (model already downloaded) ≤ 2 seconds

## Constraints
- iOS 17+ only (modern SwiftUI APIs, improved keyboard extension memory limits)
- Keyboard extension memory cap (~50 MB) means inference must run in the main
  app process, not the extension — IPC required
- transcribe.cpp must be compiled as a static library for arm64 iOS with Metal
- No paid third-party SDKs or closed-source dependencies
- Models stored in App Group container so both targets share access

## Open Questions
- Does transcribe.cpp cross-compile to iOS cleanly with the current CMakeLists?
  (needs verification via scripts/build_transcribe_ios.sh)
- Does Apple allow keyboard extensions to trigger background app launch via
  Darwin notifications for the IPC pattern? (may need to use shared memory
  or openURL instead)
- What is the minimum RAM needed to run Parakeet Q4 inference on-device?
  (determines minimum supported device)
