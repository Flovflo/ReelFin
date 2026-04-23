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

### M13
- Status: completed
- Objective: make Detail pages proactively warm the exact playback target before the user presses Play.
- Scope: `DetailViewModel`, `PlaybackWarmupManager`, `PlaybackSessionController`
- Acceptance:
  - Detail warmup passes resume position, runtime, and platform into playback warmup
  - warmup resolves playback once and preheats startup media bytes once per route/platform/resume bucket
  - active playback startup reuses the same warmup preheater path instead of duplicating untracked probes
  - series Detail warmup chooses Jellyfin Next Up, including later seasons, before falling back to the first unplayed/first episode
  - transcode/remux resume warmup does not preheat stale HLS URLs that were resolved without `StartTimeTicks`

### M14
- Status: completed
- Objective: make tvOS OK activation and upward focus return deterministic across Home, Detail, Library, Search, and top navigation.
- Scope: `HomeView`, `DetailView`, tvOS card/button components, top navigation, search and library controls
- Acceptance:
  - Continue Watching and other tvOS rails use native `Button` activation instead of focusable views with tap gestures
  - Detail rows can request a visible scroll target before transferring focus back to seasons or hero actions
  - top navigation, search, and library controls use the same native activation path as Home and Detail
  - native tvOS activation does not expose the system button chrome over custom ReelFin focus styling
  - iOS build compatibility is preserved after shared SwiftUI file changes

### M15
- Status: completed
- Objective: stop high-bitrate tvOS Direct Play from starting with zero measured AVPlayer buffer.
- Scope: `PlaybackStartupReadinessPolicy`, `PlaybackSessionController`, `DetailViewModel`
- Acceptance:
  - tvOS high-bitrate progressive Direct Play times out as unsafe instead of starting with `buffered=0.0 likely=false`
  - unsafe startup without a recovery candidate blocks autoplay rather than continuing into a predictable stall
  - repeated early Direct Play stalls before first frame trigger recovery
  - Detail warmup no longer reports progressive Direct Play as ready from disposable URLSession preheat bytes
  - measured AVPlayer buffer still starts playback when it reaches the required threshold

### M16
- Status: completed
- Objective: preserve Direct Play when AVPlayer can read the selected progressive asset, even when startup buffering telemetry is sparse.
- Scope: `PlaybackStartupReadinessPolicy`, `PlaybackSessionController`
- Acceptance:
  - tvOS high-bitrate progressive Direct Play may start after a bounded readiness timeout when AVPlayer has not reported useful buffer ranges
  - startup readiness and video-preroll timeouts no longer force Direct Play into HLS/transcode recovery
  - tvOS Direct Play skips blocking video preroll gates that can fire before the first frame exists
  - premium tvOS Direct Play gets a longer startup watchdog budget for late first frames
  - HLS resume offsets do not make the decoded-frame watchdog think playback advanced before relative HLS time moves
  - a single brief Direct Play stall after the first frame does not trigger HLS/transcode recovery

### M17
- Status: completed
- Objective: enforce the no-cut playback rule after the first visible frame while keeping Direct Play as the preferred route. Superseded by M19 for sparse progressive buffer startup telemetry.
- Scope: `PlaybackStartupReadinessPolicy`, `PlaybackSessionController`
- Acceptance:
  - high-bitrate tvOS Direct Play requires a measured startup buffer instead of starting from timeout with only a few seconds buffered
  - guarded tvOS Direct Play may recover before first frame, but does not autoplay into an unsafe progressive stream
  - tvOS premium Direct Play starts with a 90s forward-buffer target instead of waiting for a stall before ramping cache policy
  - automatic stall/failure recovery is suppressed after the first frame, so the app does not interrupt visible playback with profile reloads
  - fallback remains available before first frame when Direct Play cannot build a safe buffer

### M18
- Status: completed
- Objective: keep automatic Detail playback warmup from blocking navigation or tvOS focus before the user presses Play.
- Scope: `DetailView`, `DetailViewModelActionTests`
- Acceptance:
  - Detail-page background warmup and Direct Play preheat timeouts never show the blocking `Preparing` state
  - user-initiated playback still shows `Preparing` while the player session is loading
  - tvOS hero Play remains focusable during playback preparation, with duplicate activation ignored by the action guard
  - automatic preheat failures can fail silently in the background without trapping the Detail page

### M19
- Status: completed
- Objective: remove the false 45s tvOS Direct Play startup gate that caused long waits and transcode restarts.
- Scope: `PlaybackStartupReadinessPolicy`, `PlaybackSessionControllerTrackReloadTests`
- Acceptance:
  - high-bitrate tvOS progressive Direct Play no longer waits for measured `loadedTimeRanges` when AVPlayer reports sparse `buffered=0.0`
  - Direct Play starts from AVPlayer `readyToPlay` instead of timing out and rebuilding the session as HLS/transcode
  - startup preheat remains bounded and informative, but cannot force a 45s restart path
  - post-first-frame Direct Play stall recovery remains suppressed, so visible playback is not interrupted by profile reloads

### M20
- Status: completed
- Objective: make Direct Play mandatory and remove self-inflicted tvOS Direct Play startup waits.
- Scope: `PlaybackSessionController`, `PlaybackStartupReadinessPolicy`, `PlaybackStartupPreheater`
- Acceptance:
  - Direct Play recovery paths preserve Direct Play instead of switching to HLS/transcode
  - tvOS progressive Direct Play no longer waits for `readyToPlay` when the startup gate has zero buffer requirements
  - tvOS progressive Direct Play warmup no longer issues disposable URLSession range probes that compete with AVPlayer
  - premium tvOS Direct Play starts with the fast Direct Play buffer policy instead of a forced 90s startup target
  - tvOS cache ramp decisions use elapsed playback time since first frame, not the resumed movie position
  - resume-based HLS/transcode startup never applies an absolute deferred seek after first frame
  - Direct Play resume seeks are verified before autoplay and logged with target/current/satisfied telemetry

### M21
- Status: completed
- Objective: remove disposable progressive Direct Play preheats and shorten iOS Direct Play startup gating.
- Scope: `PlaybackStartupReadinessPolicy`, `PlaybackStartupPreheater`, `PlaybackWarmupManager`, `DetailViewModel`, `HomeView`
- Acceptance:
  - progressive Direct Play does not issue independent URLSession range probes that compete with AVPlayer on iOS or tvOS
  - iOS high-bitrate progressive Direct Play uses a ready-to-preroll gate instead of waiting for measured multi-second buffer telemetry before playback intent
  - Detail warmup still avoids marking remote progressive Direct Play as fully ready without AVPlayer-consumable evidence
  - Home featured playback presents the native player immediately and lets the session load inside the full-screen player, matching Detail startup behavior

### M22
- Status: completed
- Objective: stop early tvOS Direct Play post-start cuts without abandoning the native Apple player path.
- Scope: `PlaybackSessionController`, `PlaybackStartupReadinessPolicy`, `StartupFailureReason`
- Acceptance:
  - high-bitrate/premium tvOS progressive Direct Play starts with a 24s no-stall forward buffer target and `automaticallyWaitsToMinimizeStalling`
  - high-bitrate tvOS progressive Direct Play no longer qualifies for immediate zero-buffer startup before measured buffer telemetry
  - a Direct Play stall shortly after the first visible frame triggers direct-route-disabled recovery to a stable HLS/transcode profile
  - stale item observers ignore callbacks after item replacement, stop, or reload
  - delayed startup subtitle selection and video validation are task-owned and canceled on stop/reload/first frame

### M23
- Status: completed
- Objective: preserve compatible tvOS Direct Play as the fast path while fixing resumed fallback start positions.
- Scope: `PlaybackSessionController`, `PlaybackStartupReadinessPolicy`, Home/Library playback-quality enrichment, progress reporting
- Acceptance:
  - tvOS auto-quality progressive Direct Play stays Direct Play when the configured streaming budget has clear headroom over the source bitrate
  - preemptive HLS/transcode is limited to explicit over-budget cases instead of triggering only because a source is above 18 Mbps
  - compatible high-bitrate tvOS Direct Play skips the startup readiness delay and keeps the fast 2s/no-wait buffer policy when network headroom is known
  - strict/native quality modes still preserve Direct Play and never enter destructive H.264 fallback as a startup shortcut
  - fallback/profile re-resolution always carries the original resume `StartTimeTicks`
  - pinned HLS variant URLs preserve resume query parameters from the master playlist URL
  - startup, preroll, and preflight failures do not reload the same progressive Direct Play route that just failed
  - profile recovery suspends the old player item, observers, prerolls, and validation tasks before loading the fallback route
  - Home and Library duplicate enrichment no longer resolve playback sources or warm media routes during feed/list normalization
  - Jellyfin progress updates keep local progress responsive but throttle remote `/Sessions/Playing/Progress` reports with latest-wins behavior

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

- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests`: passed, 123 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/HomeViewModelFeedEnrichmentTests/testLoadPrefersLocalPlaybackQualityWithoutWarmupWhenDuplicateCandidatesShareTheSameMovie -only-testing:PlaybackEngineTests/LibraryViewModelTests/testLoadInitialPrefersLocalPlaybackQualityWithoutResolvingSourcesAcrossLibraries`: passed, 2 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackStopReportingTests`: passed, 125 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests`: passed, 140 tests
- `xcodegen generate`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `git diff --check`: passed
- `xcodegen generate`: passed
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests -only-testing:PlaybackEngineTests/PlaybackWarmupManagerTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackResumeSeekPlannerTests -only-testing:PlaybackEngineTests/PlaybackTVOSCachingPolicyTests`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed after rerunning sequentially
- `git diff --check`: passed
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed
- `xcodegen generate`: passed for build `1.0 (6)`
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild archive -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'generic/platform=tvOS' -archivePath .artifacts/testflight/ReelFin-tvOS-b6.xcarchive DEVELOPMENT_TEAM=WZ4CHJH7TA CODE_SIGN_STYLE=Automatic`: passed
- `xcodebuild -exportArchive -archivePath .artifacts/testflight/ReelFin-tvOS-b6.xcarchive -exportPath .artifacts/testflight/export-b6 -exportOptionsPlist .artifacts/testflight/export-b5/ExportOptions.plist`: passed
- `codesign -dv --verbose=2 /tmp/reelfin-ipa-b6/Payload/ReelFin.app` plus `Info.plist` checks: passed, `com.reelfin.app`, version `1.0`, build `6`
- `asc publish testflight --app 6762079357 --ipa .artifacts/testflight/export-b6/ReelFin.ipa --platform TV_OS --version 1.0 --build-number 6 --group "Internal Testers" --wait`: passed, build `e5c4d93a-7592-4a81-bf6e-8b1496a16238`, processing state `VALID`
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackTVOSCachingPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackResumeSeekPlannerTests`: passed, 136 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackResumeSeekPlannerTests`: passed, 128 tests
- `xcodegen generate`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/RootViewModelAuthPersistenceTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/HomeViewModelActionTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/LibraryViewModelTests`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinDetailWarmupDerivedData -only-testing:PlaybackEngineTests/PlaybackWarmupManagerTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests`: passed, 8 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStopReportingTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:ReelFinTVUITests/TVLiveNavigationSmokeUITests`: passed with 3 expected skips because no authenticated tvOS session was present in the simulator
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests/testPrepareEpisodePlaybackLatestWinsAcrossWarmupSignals`: passed, 14 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:ReelFinUITests/AppStoreScreenshotTests`: passed, 4 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/MediaGatewayCacheKeyTests -only-testing:PlaybackEngineTests/MediaGatewayIndexTests -only-testing:PlaybackEngineTests/HLSSegmentDiskCacheTests`: passed, 13 tests
- `bash -n scripts/run_zero_stall_validation.sh`: passed
- `scripts/run_zero_stall_validation.sh`: passed, artifacts in `.artifacts/zero-stall/20260419-160313`
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinZeroStallDerivedData -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed, 42 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinZeroStallDerivedData -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests`: passed, 124 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed, 57 tests
- `xcodegen generate`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests -only-testing:PlaybackEngineTests/PlaybackWarmupManagerTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed, 82 tests
- `git diff --check`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackResumeSeekPlannerTests -only-testing:PlaybackEngineTests/PlaybackTVOSCachingPolicyTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: not runnable because `PlaybackEngineTests` is not a member of the `ReelFinTV` scheme/test plan
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed, 2 tests
- `xcodegen generate`: passed for build `1.0 (5)`
- `xcodebuild archive -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'generic/platform=tvOS' -archivePath .artifacts/testflight/ReelFin-tvOS-b5.xcarchive DEVELOPMENT_TEAM=WZ4CHJH7TA CODE_SIGN_STYLE=Automatic`: passed
- `xcodebuild -exportArchive -archivePath .artifacts/testflight/ReelFin-tvOS-b5.xcarchive -exportPath .artifacts/testflight/export-b5 -exportOptionsPlist .artifacts/testflight/ExportOptions-tvOS-manual.plist`: passed
- `codesign -dv --verbose=2 /tmp/reelfin-ipa-b5/Payload/ReelFin.app` plus `Info.plist` checks: passed, `com.reelfin.app`, version `1.0`, build `5`
- `asc publish testflight --app 6762079357 --ipa .artifacts/testflight/export-b5/ReelFin.ipa --platform TV_OS --version 1.0 --build-number 5 --group "Internal Testers" --wait`: passed, build `0974cb76-e710-4f90-922f-0d5731d765c7`, processing state `VALID`
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodegen generate`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodegen generate`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed, 57 tests
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodegen generate`: passed for build `1.0 (3)`
- `xcodebuild archive -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'generic/platform=tvOS'`: passed
- `xcodebuild -exportArchive` with `.artifacts/testflight/ExportOptions-tvOS-manual.plist`: passed
- `asc publish testflight --platform TV_OS --group "Internal Testers"`: passed, build `1.0 (3)` processing state `VALID`
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/DetailViewModelActionTests`: passed, 9 tests
- `git diff --check`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodegen generate`: passed for build `1.0 (4)`
- `xcodebuild archive -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'generic/platform=tvOS'`: passed
- `xcodebuild -exportArchive` with `.artifacts/testflight/ExportOptions-tvOS-manual.plist`: passed
- `codesign` and `Info.plist` IPA verification: passed, distribution signed, `CFBundleVersion=4`
- `asc publish testflight --platform TV_OS --group "Internal Testers"`: passed, build `1.0 (4)` processing state `VALID`, build ID `d5efc767-d12f-4aa3-b6ba-67c89b43c964`
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed, 57 tests
- `git diff --check`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed, 2 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: not runnable because `PlaybackEngineTests` is not a member of the `ReelFinTV` scheme/test plan

## Explicit Deferrals

- No playback-stack replacement.
- No UIKit rewrite of SwiftUI surfaces.
- No GRDB replacement.
- No large build-graph surgery without measurement.
