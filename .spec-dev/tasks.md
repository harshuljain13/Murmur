# Tasks: handy-ios

## Phase 1: Compile transcribe.cpp for iOS
- [✓] Run build_transcribe_ios.sh and get libtranscribe.a building cleanly
- [✓] Fix any CMake / Metal / iOS SDK issues that come up
- [✓] Verify TranscribeEngine.swift links against real libtranscribe.a (swap stub header)
- [✓] Update project.yml to link libtranscribe.a and set library search path

## Phase 2: Core transcription pipeline (main app)
- [✓] Add handy:// URL scheme to Info.plist and handle it in HandyApp.swift
- [✓] Write TranscribeService.swift — loads active model, handles transcribe URL, runs inference, writes result to App Group UserDefaults
- [✓] Wire TranscribeService into HandyApp @main on launch

## Phase 3: Keyboard extension end-to-end
- [✓] Update KeyboardViewController — mic button → record → write WAV to App Group → openURL(handy://transcribe) → poll for result → insertText
- [✓] Handle "no model downloaded" state in keyboard (show prompt to open app)
- [✓] Handle timeout (30s) gracefully in keyboard UI

## Phase 4: Model download flow
- [✓] Fix ModelManager.download() — switched to URLSession downloadTask with progress
- [✓] Show download progress in ModelPickerView
- [✓] Persist active model selection across app restarts

## Phase 5: Polish + ship
- [ ] Test full flow on device: WhatsApp → Handy keyboard → mic → text inserted
- [ ] Handle mic permission denied state in keyboard
- [ ] Commit each phase as it completes
