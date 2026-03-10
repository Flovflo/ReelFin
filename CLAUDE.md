# Project: ReelFin

## Quick Reference

- Platform: iOS 26+ for iPhone and iPad
- UI: SwiftUI
- Playback stack: AVFoundation, AVKit, VideoToolbox
- Project generation: `project.yml` is the source of truth
- Architecture: modular app with `ReelFinApp`, `ReelFinUI`, `PlaybackEngine`, `JellyfinAPI`, `DataStore`, `ImageCache`, `SyncEngine`, and `Shared`

## Engineering Priorities

1. Keep playback Apple-native. No VLC, FFmpeg, or private playback APIs.
2. Preserve deterministic playback behavior and documented fallback profiles.
3. Avoid broad rewrites when a module-scoped fix is enough.
4. Keep docs, package versions, and supported platforms aligned with `project.yml`.
5. Treat `build/`, `.artifacts/`, `.claude/`, logs, and user state as local artifacts.

## Before Editing Playback

- Read `Docs/Playback-Architecture-Current.md`.
- Respect the direct-play-first model and fallback profile ordering.
- Maintain or extend tests when touching planning, HLS generation, remuxing, or subtitle logic.

## Build And Test

```bash
xcodegen generate
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```
