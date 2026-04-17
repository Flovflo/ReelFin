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

## Explicit Deferrals

- No playback-stack replacement.
- No UIKit rewrite of SwiftUI surfaces.
- No GRDB replacement.
- No large build-graph surgery without measurement.
