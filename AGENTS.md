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
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'
xcodebuild -showdestinations -project ReelFin.xcodeproj -scheme ReelFin
xcodebuild -showdestinations -project ReelFin.xcodeproj -scheme ReelFinTV
```

## Lint, Format, Typecheck

```bash
# No repo-native SwiftLint, SwiftFormat, or standalone typecheck command is configured today.
# Treat a successful xcodebuild build/test pass as the effective syntax and typecheck gate.
```

## Profiling And Performance Probes

```bash
scripts/run_player_ui_probe.sh
scripts/run_playback_qa_loop.sh
python3 scripts/test_tvos_profile.py
```

## Guardrails

- Keep the playback path Apple-native. Do not add VLC, FFmpeg, or private playback APIs.
- Prefer changes in the smallest relevant module instead of cross-cutting edits.
- Preserve async/await and actor isolation patterns in API and playback code.
- Treat `build/`, `.artifacts/`, `.claude/`, logs, and user-state files as local-only artifacts.
- Keep docs aligned with `project.yml`, especially supported platforms, package versions, and test commands.
- Preserve the current dirty worktree unless a user explicitly asks to revert it.
- Treat launch, focus, playback startup, and cache regressions as release blockers.
- Do not move hot-path behavior behind silent fallbacks that hide correctness failures.

## Do-Not-Break Rules

- Logged-out launch must reach auth/onboarding without a root spinner.
- Authenticated launch must be able to paint cached Home content before network sync completes.
- tvOS focus handoff must not depend on fixed sleeps as the primary success path.
- Playback warmup and observer work must remain cancelable and scoped to the active item/session.
- Speculative artwork prefetch must not bypass authenticated image loading or poison cache keys.

## Performance Definition Of Done

- `xcodegen generate` succeeds after source changes.
- `ReelFin` and `ReelFinTV` build on the current local simulator runtimes.
- Targeted tests covering launch/auth state, Home loading, Library loading, playback, and tvOS focus still pass.
- New hot-path async work is latest-wins, cancelable, and does not broaden `MainActor` usage.
- Launch, sync, focus, playback, and artwork prefetch changes are recorded in `PLANS.md` and `OPTIMIZATION_AUDIT.md`.
