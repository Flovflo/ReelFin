<div align="center">
  <img src="https://raw.githubusercontent.com/jellyfin/jellyfin-ux/master/branding/SVG/icon-transparent.svg" alt="Jellyfin logo" width="120" height="120">
  <h1>ReelFin</h1>
  <p><strong>Native Jellyfin client for iPhone, iPad, and Apple TV</strong></p>
  <p>
    <img src="https://img.shields.io/badge/Platform-iOS%20%26%20tvOS%2026%2B-blue.svg" alt="Platform">
    <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift">
    <img src="https://img.shields.io/badge/UI-SwiftUI-informational.svg" alt="SwiftUI">
    <img src="https://img.shields.io/badge/Status-Beta-success.svg" alt="Status">
  </p>
</div>

ReelFin is a native Jellyfin app focused on deterministic playback, modern SwiftUI interfaces, and Apple-first media pipelines. The project avoids VLC-style embedded stacks and instead leans on `AVFoundation`, `AVKit`, and `VideoToolbox` to keep playback debuggable, efficient, and App Store friendly across iPhone, iPad, and Apple TV.

## Why ReelFin

- Native Jellyfin playback path across iPhone, iPad, and Apple TV
- Direct-play-first decision engine for Apple-compatible streams
- On-device remux path for MKV to fragmented MP4 when needed
- Deterministic fallback profiles instead of opaque playback heuristics
- Modular Swift codebase with separate UI, API, cache, sync, data, and playback layers
- Built-in diagnostics for playback planning and runtime troubleshooting

## Feature Highlights

- Apple-native playback through `AVPlayer`
- HEVC, HDR10, and Dolby Vision aware playback planning
- Jellyfin home feed, library browsing, detail pages, search, and settings
- tvOS-first focus navigation, cinematic shelves, and Apple TV optimized layouts
- Local metadata persistence with GRDB
- Image pipeline with memory and disk cache
- Test coverage around playback planning, HLS generation, subtitles, and image cache behavior

## Architecture

### Core modules

- `ReelFinApp`: iOS and tvOS app bootstrap and dependency container
- `ReelFinUI`: shared SwiftUI screens, theming, tvOS shells, and view models
- `PlaybackEngine`: playback planning, native bridge, local HLS server, subtitle strategy
- `JellyfinAPI`: async/await network client and DTO decoding
- `DataStore`: GRDB-backed metadata repository
- `ImageCache`: memory and disk image pipeline
- `SyncEngine`: sync orchestration
- `Shared`: domain models, protocols, settings, logging, app metadata

### Playback flow

1. `JellyfinAPI` resolves media sources and metadata.
2. `PlaybackEngine` evaluates Apple compatibility and builds a playback plan.
3. ReelFin attempts direct play first.
4. If needed, ReelFin falls back to local remux or server transcode profiles.
5. `PlaybackSessionController` manages `AVPlayer`, diagnostics, watchdogs, and recovery.

For the detailed playback contract, see `Docs/Playback-Architecture-Current.md`.

## Repository Guide

- `project.yml` is the source of truth for targets, dependencies, and schemes.
- `ReelFin.xcodeproj` is generated output and should stay aligned with `project.yml`.
- `AppStore/Screenshots` contains curated release screenshots.
- `build/`, `.artifacts/`, `.claude/`, logs, and user state are local artifacts and should not be versioned.
- `AGENTS.md` and `llms.txt` are included to help coding agents and LLM tooling navigate the repo quickly.

## Development

### Requirements

- Xcode with iOS 26 and tvOS 26 simulators installed
- XcodeGen available in your local environment

### Generate the project

```bash
xcodegen generate
```

### Build

```bash
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'

xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
```

### Test

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

### Focused playback tests

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests \
  -only-testing:PlaybackEngineTests/Planning/CapabilityEngineTests
```

## LLM And Contributor Context

If you are working on the repo with an AI agent or joining the project as a new contributor:

- read `AGENTS.md` for repo conventions
- read `Docs/Playback-Architecture-Current.md` before touching playback logic
- keep the playback path Apple-native
- prefer targeted module changes over broad rewrites
- keep docs aligned with `project.yml`

## App Store And Support

- App Store submission notes: `Docs/AppStore-Submission.md`
- TestFlight checklist: `Docs/TestFlight-Launch-Checklist.md`
- App Review notes template: `Docs/AppReview-Notes.md`
- Public support site source: `Site/`
- GitHub Pages workflow: `.github/workflows/deploy-site.yml`
- Release preflight script: `scripts/preflight_testflight_release.sh`

## Keywords

Jellyfin iOS client, native Jellyfin app, SwiftUI media app, AVFoundation player, Apple-native video playback, iPhone Jellyfin app, iPad Jellyfin client.
