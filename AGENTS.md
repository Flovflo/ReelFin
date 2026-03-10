# ReelFin Agent Guide

## Project Summary

ReelFin is a native iPhone and iPad Jellyfin client built with SwiftUI and Apple playback frameworks. The repo is organized as a modular XcodeGen project with a single source of truth in `project.yml`.

## Source Of Truth

- `project.yml`: XcodeGen configuration. Update this file first when targets, dependencies, or schemes change.
- `ReelFin.xcodeproj`: generated project output. Regenerate instead of hand-editing when possible.

## Repository Map

- `ReelFinApp/`: app entry point and bootstrap wiring
- `ReelFinUI/`: SwiftUI screens, themes, and view models
- `PlaybackEngine/`: playback planning, local HLS, native bridge, subtitles
- `JellyfinAPI/`: Jellyfin networking client and DTO decoding
- `DataStore/`: GRDB-backed metadata persistence
- `ImageCache/`: memory + disk image pipeline
- `SyncEngine/`: background sync orchestration
- `Shared/`: domain models, protocols, settings, logging
- `Tests/`: unit and UI tests
- `Docs/`: product, playback, and App Store support documents
- `scripts/`: maintenance scripts kept in the repo on purpose
- `AppStore/Screenshots/`: curated screenshots for release assets

## Build And Test

```bash
xcodegen generate
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

## Guardrails

- Keep the playback path Apple-native. Do not add VLC, FFmpeg, or private playback APIs.
- Prefer changes in the smallest relevant module instead of cross-cutting edits.
- Preserve async/await and actor isolation patterns in API and playback code.
- Treat `build/`, `.artifacts/`, `.claude/`, logs, and user-state files as local-only artifacts.
- Keep docs aligned with `project.yml`, especially supported platforms, package versions, and test commands.
