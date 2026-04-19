# ReelFin Optimization Plan

## Milestones

### M0
- Status: completed
- Objective: establish one source of truth for performance work, commands, and acceptance gates.
- Scope: `AGENTS.md`, `PLANS.md`, `OPTIMIZATION_AUDIT.md`
- Acceptance:
  - repo map, build/test/profile commands, and do-not-break rules are documented
  - top-ranked fixes and fake-optimization rejects are written down

### M1
- Status: completed
- Objective: remove avoidable launch blocking before first usable frame.
- Scope: app bootstrap, root auth gating, foreground sync entry
- Acceptance:
  - persisted auth/onboarding state is available synchronously
  - logged-out launch does not depend on the root spinner
  - foreground sync does not run when there is no active session

### M2
- Status: completed
- Objective: make authenticated Home first paint independent from metadata freshness.
- Scope: `HomeViewModel`
- Acceptance:
  - cached/stale Home can render before app-launch sync finishes
  - sync still enriches the cache in the background

### M3
- Status: completed
- Objective: give Library a single latest-wins request pipeline for search, filter, sort, and pagination.
- Scope: `LibraryView`, `LibraryViewModel`
- Acceptance:
  - stale library requests cannot overwrite newer criteria
  - grid state changes at most once for cache and once for remote per intent

### M4
- Status: planned
- Objective: narrow SwiftUI invalidation surfaces on Home and Detail.
- Scope: `HomeView`, `DetailView`, `StickyBlurHeader`
- Acceptance:
  - scroll-linked state is isolated from large content trees
  - hot rows do not re-render on unrelated focus or hydration work

### M5
- Status: completed
- Objective: reduce iOS detail render cost by using cheaper preview-card artwork paths.
- Scope: `DetailView`, hero background helpers, carousel preview helpers
- Acceptance:
  - non-selected cards avoid hero-grade backdrop requests

### M6
- Status: completed
- Objective: remove self-inflicted tvOS focus latency and restore scheme validation.
- Scope: `TVRootShellView`, tvOS focus handoff helpers, `ReelFinTVUITests`
- Acceptance:
  - root focus handoff is content-driven instead of sleep-driven
  - tvOS UI tests compile without unavailable `tap()` usage
  - targeted tvOS smoke tests run cleanly and skip when no persisted tvOS session exists

### M7
- Status: completed
- Objective: harden detail/playback freshness and task ownership without changing the external playback boundary.
- Scope: `DetailViewModel`
- Acceptance:
  - season and episode selection work is latest-wins
  - stale episode warmup/progress work cannot overwrite the current selection

### M8
- Status: completed
- Objective: warm decoded artwork cache on speculative paths and strengthen regression resistance.
- Scope: image prefetch helpers, `JellyfinAPIClient`, `DefaultImagePipeline`, tests
- Acceptance:
  - speculative artwork prefetch reaches `DefaultImagePipeline`
  - duplicate prefetch work is deduplicated

### M9
- Status: completed
- Objective: cancel stale playback delayed work and remove dead repo artifacts that no longer have a backing workflow.
- Scope: `PlaybackSessionController`, `NativePlayerViewController`, stale task/docs/scripts
- Acceptance:
  - delayed playback validation, synthetic seek invalidation, and synthetic prefetch work are canceled on stop/reload
  - native trickplay preview updates do not allocate a new MainActor task every 150 ms tick
  - obviously stale repo artifacts are removed only when they are unreferenced or point at deleted code

### M10
- Status: completed
- Objective: reduce visible startup stalls while keeping resume and detail warmup latest-wins.
- Scope: `PlaybackSessionController`, startup readiness policy, startup preheater, `DetailViewModel`
- Acceptance:
  - high-risk playback starts wait for bounded buffer readiness before autoplay
  - direct-play preheat avoids byte-range probes for HLS playlists
  - startup preheat overlaps AVPlayer preparation instead of blocking the player handoff
  - stale episode warmup/progress work cannot overwrite the current detail playback target

### M11
- Status: completed
- Objective: establish durable, token-safe media cache foundations for zero-stall playback work.
- Scope: `MediaGatewayCacheKey`, `MediaGatewayIndex`, `HLSSegmentDiskCache`, zero-stall validation runner
- Acceptance:
  - media cache keys are stable, route-aware, resume-bucketed, and do not persist raw secrets
  - the media gateway index persists TTL/LRU metadata and recovers safely from corrupt index data
  - HLS playlists, init segments, and media segments can be stored on disk with TTL and LRU eviction
  - zero-stall validation has one repeatable script entry point for iOS/tvOS build and targeted startup tests

### M12
- Status: completed
- Objective: keep high-bitrate iOS DirectPlay startup audiovisual-synchronized without reintroducing long visible waits.
- Scope: `PlaybackSessionController`, startup readiness policy
- Acceptance:
  - DirectPlay startup remains paused until the bounded readiness gate finishes
  - iOS DirectPlay does not start after a readiness timeout unless AVPlayer reports measured buffer
  - measured preferred buffer wins over a late timeout sample instead of triggering a false fallback
  - iOS DirectPlay prerolls a video frame before allowing audio playback to start
  - iOS DirectPlay preroll failures recover via a safer playback profile instead of starting audio-only
  - startup DirectPlay recovery preserves the original resume position via `StartTimeTicks`
  - startup DirectPlay stalls fall back to HLS/transcode recovery instead of reloading the same progressive URL or another direct route
  - iOS high-bitrate DirectPlay uses a smaller no-stall buffer target instead of a 30s startup-heavy target
  - first-frame telemetry requires an actual video pixel buffer when a video output is attached

## Validation Commands

```bash
xcodegen generate
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/RootViewModelAuthPersistenceTests
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/HomeViewModelActionTests
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/LibraryViewModelTests
scripts/run_player_ui_probe.sh
scripts/run_playback_qa_loop.sh
scripts/run_zero_stall_validation.sh
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:ReelFinTVUITests/TVLiveNavigationSmokeUITests
```

## Latest Validation

- `xcodegen generate`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/RootViewModelAuthPersistenceTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/HomeViewModelActionTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/LibraryViewModelTests`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStopReportingTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:ReelFinTVUITests/TVLiveNavigationSmokeUITests`: passed with 3 expected skips because no authenticated tvOS session was present in the simulator
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests/testPrepareEpisodePlaybackLatestWinsAcrossWarmupSignals`: passed, 14 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:ReelFinUITests/AppStoreScreenshotTests`: passed, 4 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/MediaGatewayCacheKeyTests -only-testing:PlaybackEngineTests/MediaGatewayIndexTests -only-testing:PlaybackEngineTests/HLSSegmentDiskCacheTests`: passed, 13 tests
- `bash -n scripts/run_zero_stall_validation.sh`: passed
- `scripts/run_zero_stall_validation.sh`: passed, artifacts in `.artifacts/zero-stall/20260419-160313`
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinZeroStallDerivedData -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed, 42 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinZeroStallDerivedData -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests`: passed, 124 tests
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed

## Explicit Deferrals

- No playback-stack replacement.
- No UIKit rewrite of SwiftUI surfaces.
- No GRDB replacement.
- No large build-graph surgery without measurement.
