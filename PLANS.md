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
  - iOS high-bitrate progressive DirectPlay waits for measured AVPlayer buffer headroom before autoplay instead of accepting a 0s/readyToPlay-only gate
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
  - ordinary compatible tvOS Direct Play can skip the startup readiness delay and keep the fast 2s/no-wait buffer policy when network headroom is known
  - strict/native quality modes still preserve Direct Play and never enter destructive H.264 fallback as a startup shortcut
  - fallback/profile re-resolution always carries the original resume `StartTimeTicks`
  - pinned HLS variant URLs preserve resume query parameters from the master playlist URL
  - startup, preroll, and preflight failures do not reload the same progressive Direct Play route that just failed
  - profile recovery suspends the old player item, observers, prerolls, and validation tasks before loading the fallback route
  - Home and Library duplicate enrichment no longer resolve playback sources or warm media routes during feed/list normalization
  - Jellyfin progress updates keep local progress responsive but throttle remote `/Sessions/Playing/Progress` reports with latest-wins behavior

### M24
- Status: completed
- Objective: fix Direct Play black-screen recovery without abandoning the fast native path.
- Scope: `PlaybackSessionController`, `StartupFailureReason`, playback policy tests
- Acceptance:
  - compatible tvOS Direct Play still starts as Direct Play when selected and network headroom is available
  - `audio_only_no_video`, decoded-frame watchdog, zero presentation size, and player-item failure no longer reload the same progressive Direct Play URL
  - black-screen/profile recovery disables direct routes and suspends the old player item before loading the fallback route
  - `directplay_stall` remains the only failure reason allowed to attempt same-route Direct Play recovery
  - the new `audio_only_no_video` reason is structured, triggers recovery, and round-trips through `StartupFailureReason`

### M25
- Status: completed
- Objective: keep strict native mode on the sample-buffer engine while making its tvOS chrome closer to Apple player visuals.
- Scope: `NativePlayerPlaybackController`, `PlaybackSessionController`, `PlayerView`, native route guard, native playback tests
- Acceptance:
  - original MP4/MOV with Apple-compatible codecs routes to the native sample-buffer surface, not `AVPlayerViewController`
  - original Matroska with Apple-compatible codecs routes through `MatroskaDemuxer` and the native sample-buffer surface, not loopback fMP4/HLS
  - strict native mode does not create `AVPlayerItem` and does not use `AVPlayerViewController`
  - Jellyfin `/master.m3u8`, `/main.m3u8`, forced-transcode query parameters, and loopback local HLS remain blocked for native original mode
  - visible route logs use the `nativeplayer.*` prefix consistently
  - the sample-buffer player exposes the stable `native_engine_player_screen` UI-test anchor

### M26
- Status: completed
- Objective: preserve HDR and Dolby Vision metadata through both Apple Direct Play and native sample-buffer playback.
- Scope: `NativeMediaCore`, `NativePlayerViewController`, native sample-buffer player views, HDR diagnostics
- Acceptance:
  - Matroska and MP4 demuxing carry HDR metadata into `MediaTrack`
  - HEVC `CMVideoFormatDescription` creation includes CoreMedia color primaries, transfer function, YCbCr matrix, and bit-depth extensions
  - MP4 sample-buffer playback keeps compressed video samples instead of forcing 8-bit decoded pixel buffers
  - iOS Direct Play asks AVKit for high dynamic range playback and tvOS Direct Play lets AVKit apply preferred display criteria automatically
  - tvOS sample-buffer playback publishes `AVDisplayCriteria` from the first video sample format description
  - diagnostics report HDR format and Dolby Vision profile instead of silently claiming unknown playback quality

### M27
- Status: completed
- Objective: keep iOS native Direct Play on stable Jellyfin original-file URLs without post-start self-reloads.
- Scope: `PlaybackSessionController`, Direct Play AVAsset options, resume startup and stall policy
- Acceptance:
  - guarded MP4/MOV Direct Play resolves `/stream.mp4` up front and remains Direct Play, not transcode
  - extensionless MP4/MOV Direct Play supplies an AVFoundation MIME override only when a stable extension is unavailable
  - Direct Play resume seek is applied as soon as the current `AVPlayerItem` becomes ready, before first-frame telemetry or autoplay
  - unsafe readiness or video-preroll failures block autoplay instead of force-playing a failed/high-risk item
  - iOS post-first-frame Direct Play stalls keep the current `AVPlayerItem`, raise the forward-buffer target, and let AVPlayer re-buffer instead of reloading the same `/stream`
  - Direct Play remains the selected route; no automatic HLS/transcode fallback is introduced for this fix

### M28
- Status: completed
- Objective: make the iOS auto-quality player choose the stable Apple HLS path before high-risk progressive Direct Play can visibly stall.
- Scope: `PlaybackSessionController`, `PlaybackCoordinator`, Direct Play route guard recovery
- Acceptance:
  - auto quality may preempt iOS high-bitrate progressive MP4/MOV Direct Play when SDR fallback is allowed and audio likely needs transcode
  - strict-quality and Direct/Remux-only policies preserve the native Direct Play route
  - tvOS remains on its existing Direct Play policy and does not inherit the iOS preemptive HLS path
  - native route guard still blocks accidental legacy coordinator use, but allows explicit recovery/preemption reasons
  - simulator playback on the real Jellyfin item shows HLS transcode selection, moving frames, and no app-level stall/failure markers

### M29
- Status: completed
- Objective: stabilize high-bitrate tvOS progressive Direct Play without falling back away from the native Apple path.
- Scope: `PlaybackSessionController`, tvOS Direct Play stability tests
- Acceptance:
  - high-bitrate/premium tvOS progressive Direct Play no longer treats configured network headroom as enough proof to bypass no-stall buffering
  - those tvOS Direct Play sources keep the 24s forward-buffer target and `automaticallyWaitsToMinimizeStalling`
  - ordinary lower-risk tvOS Direct Play still uses the fast 2s/no-wait path when the configured streaming budget has clear headroom
  - tvOS continues to preserve Direct Play and does not inherit the iOS preemptive HLS fallback
- Validation: targeted red/green playback policy tests, focused PlaybackEngine startup tests, `ReelFinTV` build/test, and `scripts/run_reelfin_player_e2e.sh --skip-ui --loops 1 --sample-size 4 --max-failures 1` passed with artifacts `.artifacts/player-e2e/20260428-202226`.

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
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinAppleTransmuxDD -only-testing:PlaybackEngineTests/NativeApplePlaybackRoutePlannerTests -only-testing:PlaybackEngineTests/NativePlayerRouteGuardTests -only-testing:PlaybackEngineTests/NativePlayerSessionRoutingTests -only-testing:PlaybackEngineTests/NativePlayerPlaybackControllerEndToEndTests`: passed, 19 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinAppleTransmuxDD -only-testing:PlaybackEngineTests`: passed, 442 tests, 4 expected skips
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinAppleTransmuxUITestDD3 -only-testing:ReelFinUITests/AppStoreScreenshotTests/testCapturePlayerScreenshot`: passed
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinAppleTransmuxFullIOSDD2`: passed
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -derivedDataPath /tmp/ReelFinAppleTransmuxFullTVDD2`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinAppleTransmuxIOSBuildDD`: historical pass before M28; sample-buffer deprecation warnings resolved in M28
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -derivedDataPath /tmp/ReelFinAppleTransmuxTVBuildDD`: historical pass before M28; sample-buffer deprecation warnings resolved in M28
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
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinBlackScreenDD -only-testing:PlaybackEngineTests/PlaybackPolicyTests/testStartupRecoveryDisablesDirectRoutesForUnsafeProgressiveFailures -only-testing:PlaybackEngineTests/PlaybackPolicyTests/testStartupFailureReasonAudioOnlyNoVideoTriggersRecovery -only-testing:PlaybackEngineTests/PlaybackPolicyTests/testStartupFailureReasonRawValueRoundTrip -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests/testStartupDirectPlayFailuresSkipSameRouteRecovery -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests/testVideoDecodeFailuresDisableDirectRouteRecovery`: passed, 5 tests
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
- `xcodegen generate`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/HDRMetadataTests -only-testing:PlaybackEngineTests/VideoCodecPrivateDataParserTests -only-testing:PlaybackEngineTests/NativePlaybackPlannerTests`: passed, 19 tests
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `git diff --check`: passed
- Legacy native-player naming scan across docs/source/tests: passed with no matches
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

## Native Engine Player Branch - 2026-04-23

- Added `NativeMediaCore` and `NativeMediaCoreTV` targets behind `NativePlayerConfig.enabled`, default off.
- Added local-first original media resolver, HTTP range source, byte probing, demuxer protocols, MP4 helper demuxer, Matroska EBML/tracks/basic packet parsing, decode/render/audio/subtitle/HDR/planner/diagnostics foundations.
- Added a separate native diagnostics player surface so the existing AVPlayer route remains unchanged when the flag is off.
- Added end-to-end sample-buffer playback paths for original MP4 and Matroska through native sample extraction, `AVSampleBufferDisplayLayer`, `AVSampleBufferAudioRenderer`, and live diagnostics without Jellyfin HLS/transcode fallback.
- Fixed the first native Matroska stutter loop: E-AC3/AC-3/AAC laced audio packets now synthesize codec packet durations when Matroska omits `DefaultDuration`, streaming clusters apply the same timing, duplicate compressed-audio PTS values are normalized before enqueue, and audio rebuffering requires consecutive starvation ticks instead of one jitter sample.
- Fixed the second native Matroska stutter loop from runtime logs: startup/rebuffer no longer treats local queued audio as renderer-ready audio, `buffering.ready` now requires 32 audio samples accepted by `AVSampleBufferAudioRenderer` for initial start and 16 after rebuffer, audio uses `requestMediaDataWhenReady` instead of a 10 ms polling timer, and the native player stops/publishes progress when the SwiftUI player surface disappears.
- Fixed the third native Matroska stutter loop from runtime logs: `audioPackets=32` with `audioAhead=10.624` made the next risk visible at the audio timeline/renderer boundary; the audio timing normalizer now rewrites both backward/duplicate and forward PTS discontinuities to `lastPTS + packetDuration`, diagnostics expose `maxAudioPTSCorrection`, and compressed-audio rebuffering now requires sustained starvation time instead of a burst of tight `requestMediaDataWhenReady` callbacks.
- Fixed the fourth native Matroska stutter loop from runtime/code analysis: AC-3/E-AC-3 Matroska blocks can carry multiple Dolby syncframes, but the compressed audio builder was publishing the whole block as one `CMSampleBuffer` sample. It now parses Dolby frame sizes and emits multi-sample compressed buffers with per-frame timing, preventing regular audio gaps caused by false one-frame durations.
- Fixed the fifth native playback continuity loop from the latest logs: SwiftUI diagnostics/progress updates were able to re-enter `configure` and reapply `AVSampleBufferRenderSynchronizer.setRate(1, time: currentTime)` even when pause state had not changed, which can create small audio+video discontinuities. Native MP4/Matroska controllers now gate pause/rate applications, ignore live `startTimeSeconds` drift for the same playback URL, avoid pausing the whole synchronizer on transient audio starvation, and require a deeper Matroska startup buffer before first play.
- Fixed the sixth native startup loop from the latest buffering logs: the route/probe/demux/renderers were correct, but playback could wait forever for compressed audio priming after video was ready. Matroska startup now uses a bounded audio watchdog that is not reset by transient starvation callbacks, logs `nativeplayer.buffering.wait` with exact readiness blockers, treats `AVSampleBufferAudioRenderer` failure as a precise audio failure, and can degrade audio startup to let video play instead of staying stuck in buffering.
- Optimized native Matroska first-frame startup after the Ready Player One-style slow-start logs: initial playback now uses a short renderer-prime threshold (`requiredAudioPrimed=8`, `requiredAudioAhead=1.25`, `requiredVideoAhead=1.25`) while keeping the deeper 32-sample/6-8s thresholds for true rebuffer recovery. A healthy Dolby renderer that reports `audioPrimed=24` and multi-second audio/video ahead can now start immediately instead of waiting for the old 32-sample gate or watchdog degradation.
- Replaced the always-visible native diagnostics wall with a tvOS-style Liquid Glass transport overlay. The native player now exposes back, play/pause, skip, scrub/progress, diagnostics toggle, tvOS exit/play-pause commands, and a tvOS-specific focusable scrubber instead of using unavailable `Slider` APIs.
- Refined the native transport chrome to match the Apple tvOS player reference more closely: metadata now sits bottom-left over the video, the timeline is a thin full-width bar with current/remaining time labels, action pills use Liquid Glass capsules, and the secondary controls are round Liquid Glass icon buttons instead of a framed control card.
- Removed the transport scrim/black background from the native chrome, stopped the parent player view from painting a black backdrop behind the sample-buffer route, switched player chrome controls to local `Glass.clear` surfaces, disabled default tvOS focus chrome on those buttons, and added an auto-hide policy so the overlay disappears after a short idle delay during clean playback while staying visible for pause, buffering, diagnostics, and errors.
- Validation: `xcodegen generate` passed; Matroska/audio/buffer/MP4 runtime tests passed 23 tests; native route/session/stop tests passed 15 tests; iOS `ReelFin` build passed; tvOS `ReelFinTV` build passed; tvOS simulator launch logged `nativeplayer.runtime.enabled`.
- Latest validation: clean DerivedData native playback continuity suite passed 36 tests, including MP4 runtime pumping and Matroska parser/audio timing/buffer policies; iOS `ReelFin` and tvOS `ReelFinTV` builds passed after the pause/rate gating and deeper Matroska buffer changes.
- Latest validation after startup watchdog: clean DerivedData focused startup/buffer/config tests passed 14 tests; broader native playback continuity suite passed 41 tests; iOS `ReelFin` build passed; tvOS `ReelFinTV` build passed.
- Latest validation after fast-start/chrome pass: `xcodegen generate` passed; focused startup/config tests passed; iOS `ReelFin` and tvOS `ReelFinTV` builds passed. tvOS compile caught the unavailable SwiftUI `Slider`, which is now replaced by a native focusable progress scrubber.
- Latest validation after Apple-like chrome pass: `xcodegen generate` passed; `NativePlayerConfigurationTests` passed 6 tests including chrome presentation formatting; tvOS `ReelFinTV` simulator build passed.
- Latest validation after no-scrim auto-hide chrome pass: `xcodegen generate` passed; focused native player route/chrome tests passed 24 tests and confirmed sample-buffer routing with `avPlayerItem=false` and `avPlayerViewController=false`.
- Latest validation after transparent native player backdrop: `NativePlayerConfigurationTests` passed 8 tests; tvOS `ReelFinTV` simulator build passed.
- Optimized tvOS native seeking after logs showed many `nativeplayer.sampleReader.start` events from one remote scrub interaction. Horizontal remote moves now coalesce before committing a seek, the timeline keeps the optimistic target visible instead of snapping back to zero/current playback, and Matroska forward seeks stay on the current demuxer/HTTP reader when the target is ahead of the current playhead.
- Refined the Liquid Glass controls after visual review: player buttons now use clear interactive native glass instead of material-heavy blurred fills, default tvOS focus/hover halos are disabled on the custom controls, and the progress scrubber is a thin timeline without the oversized white capsule halo.
- Latest validation after seek/chrome polish: `xcodegen generate` passed; focused native player configuration and buffer policy tests passed 20 tests; tvOS `ReelFinTV` simulator build passed.
- Fixed seek corruption after a forward-skip runtime log showed repeated `nativeplayer.seek.forward_in_place` commits followed by a visibly corrupted HEVC/Dolby Vision frame. Native Matroska forward seek now refuses to decode video until it reaches a safe video keyframe, the normal Matroska demuxer seek fallback also repositions to a loaded video keyframe instead of an arbitrary packet, and repeated remote seeks now debounce for 650 ms so multiple right-arrow presses accumulate into one committed seek.
- Latest validation after keyframe-safe seek: `xcodegen generate` passed; focused `NativePlayerConfigurationTests` + `MatroskaParserTests` passed 27 tests; tvOS `ReelFinTV` simulator build passed.
- Optimized native Matroska resume startup for files without usable cues. Resume from the middle of a large MKV no longer falls back to the first loaded cluster and then scans/decodes from the beginning; the demuxer now estimates a byte-range near the requested resume time, scans that window for valid Matroska cluster headers/timecodes, and starts from the closest safe cluster at or before the target. The sample-buffer player also applies the keyframe/preroll packet filter during initial resume, not only during interactive forward seek, so pre-target packets are skipped before decode whenever possible.
- Removed the round tvOS timeline knob from the custom native chrome and replaced it with a thin vertical playhead marker to better match the Apple reference player.
- Preserved HDR/Dolby Vision display metadata through the native pipeline: Matroska and MP4 now attach HDR metadata to `MediaTrack`, HEVC sample-buffer format descriptions carry CoreMedia color tags, MP4 native playback no longer forces 8-bit pixel output, Direct Play configures AVKit for HDR-capable presentation, and tvOS sample-buffer playback publishes `AVDisplayCriteria` from the first video sample.
- Latest validation after HDR/Dolby Vision metadata pass: `xcodegen generate` passed; focused HDR/planner/decoder propagation tests passed 19 tests; tvOS `ReelFinTV` simulator build passed; `git diff --check` passed; the main source/docs/test paths have no remaining legacy native-player naming matches.
- Explicit limitation: I could install and launch the tvOS app, but runtime playback of the exact Jellyfin film still needs a signed-in simulator/device session; unsupported codec backends still report exact reasons instead of silently transcoding.
- Optimized native Matroska resume and rapid seeking after logs showed resume startup reading from the beginning and repeated remote seeks waiting for fresh audio/video buffers. The demuxer now parses SeekHead, range-loads Cues located after the initial 8 MB probe, marks those streams seekable, and caches discovered cluster timecodes from loaded or scanned windows. Interactive forward seek now applies `demuxer.seek(to:)` before keyframe/preroll filtering, so right-arrow jumps reposition the byte reader instead of flushing buffers and linearly skipping packets.
- Latest validation after SeekHead-backed resume and demuxer-applied forward seek: `xcodegen generate` passed; `git diff --check` passed; focused `MatroskaParserTests` + `NativePlayerConfigurationTests` passed 29 tests, including late-file Cues loading and approximate cue-less seek fallback; tvOS `ReelFinTV` simulator build passed.
- Fixed tvOS Direct Play HDR/Dolby Vision startup after logs showed `AVPlayerItem.status=readyToPlay` followed by `VRP`/`FigCaptionRenderPipeline` failures and no first-frame telemetry. Progressive tvOS Direct Play HDR/DV no longer attaches the 8-bit `AVPlayerItemVideoOutput` probe, so AVKit owns the HDR/DV render pipeline; it also skips auto-selecting default non-forced embedded subtitles on that path while preserving forced and manual subtitle selection.
- Latest validation after tvOS Direct Play render/caption guard: `xcodegen generate` passed; focused `PlaybackSessionControllerTrackReloadTests` passed 60 tests; tvOS `ReelFinTV` simulator build passed.
- Fixed a tvOS sample-buffer threading violation from the latest crash log: `applyPreferredDisplayCriteriaIfNeeded` was touching `UIViewController.view/window` from `reelfin.nativeplayer.mkv.video`. MP4 and Matroska sample-buffer players now route `AVDisplayCriteria` apply/reset through a generation-guarded main-thread coordinator, so video queues only inspect `CMSampleBuffer` metadata and never access UIKit.
- Latest validation after display-criteria threading fix: `xcodegen generate` passed; focused `NativePlayerConfigurationTests` passed 15 tests; tvOS `ReelFinTV` simulator build passed; tvOS `ReelFinTV` tests passed 2 tests.
- Fixed the tvOS Apple-compatible Direct Play regression from the latest `2050da6b` logs. Original MP4/MOV sources with Apple-supported container, video codec, and audio codec now short-circuit directly to `AVPlayerViewController` before `HTTPRangeByteSource`, probing, `MP4Demuxer`, or `AVAssetReader` are created. The expected healthy log is `nativeplayer.apple.route.selected ... nativeProbe=false`; `nativeplayer.byteSource.open`, `nativeplayer.probe.start`, and `MP4Demuxer` should be absent for this Direct Play file.
- Latest validation after Direct Play short-circuit: `xcodegen generate` passed; focused `NativePlayerPlaybackControllerEndToEndTests`, `NativePlayerSessionRoutingTests`, `NativePlayerConfigurationTests`, and `PlaybackSessionControllerTrackReloadTests` passed 84 tests; tvOS `ReelFinTV` simulator build passed; `git diff --check` passed.
- Fixed the iOS native Direct Play warmup/stall loop from the `2050da6b` logs. Native mode no longer clears playback warmup, warmup now resolves original-file Direct Play via the native original resolver instead of the legacy coordinator, and guarded progressive Direct Play performs an authenticated Range preheat for resume/high-bitrate startup. The Apple-native route can reuse a warmed Direct Play selection, consumes cached preheat evidence before autoplay, and resolves MP4/MOV originals to Jellyfin's stable `/stream.mp4?static=true` endpoint while preserving Direct Play; non-Apple originals such as MKV stay on `/stream`.
- Latest validation after native Direct Play warmup/no-alias pass: `xcodegen generate` passed; targeted red tests failed before implementation and now pass; focused `PlaybackSessionControllerTrackReloadTests`, `PlaybackStartupReadinessPolicyTests`, `PlaybackWarmupManagerTests`, `PlaybackStartupPreheaterTests`, `DetailViewModelActionTests`, `NativePlayerRouteGuardTests`, and `NativePlayerSessionRoutingTests` passed 116 tests; `git diff --check` passed; iOS `ReelFin` simulator build passed; tvOS `ReelFinTV` simulator build passed with existing sample-buffer deprecation warnings only.
- Fixed the iOS post-start Direct Play stall loop from the latest `2050da6b` logs. After first frame, iOS no longer reloads the same `/stream` item on repeated stalls; it keeps the current item, increases the forward-buffer target to 24s, and lets AVPlayer re-buffer the existing Direct Play stream.
- Latest validation after iOS post-start stall handling: targeted red test failed before implementation and now passes; focused playback/native/detail suite passed; `xcodegen generate`, iOS `ReelFin` build, tvOS `ReelFinTV` build, and `git diff --check` passed.
- Fixed the follow-up iOS Direct Play black-video regression from the `2050da6b` logs. HDR/Dolby Vision progressive Direct Play on iPhone no longer treats a decoded `AVPlayerItemVideoOutput` pixel buffer as proof that the user-visible AVKit surface is rendering; first-frame telemetry now requires `AVPlayerViewController.isReadyForDisplay`, and the controller re-checks that state after render-surface reattach so an early ready signal is not lost.
- Latest validation after AVKit display-proof fix: targeted red test failed before implementation and now passes; focused `PlaybackSessionControllerTrackReloadTests` and `NativePlayerConfigurationTests` checks passed.
- Fixed the follow-up resume cut on iOS Direct Play. The `2050da6b` log showed `avplayer.first-frame ... currentTime=0.000` followed by `Deferred resume seek applied at 1546.112s`, then a stall. Direct Play resume startup now refuses to mark first-frame while a pending resume target is not satisfied, forcing the preplay resume seek to land before TTFF/first-frame telemetry and before user-visible playback starts.
- Fixed the follow-up iOS Direct Play micro-stalls. The latest logs showed Direct Play and resume ordering were correct, but autoplay still started from shallow measured buffers (`buffered=3.3`, then `buffered=6.7 likely=true`) and stalled roughly when that buffer drained. iOS high-bitrate progressive Direct Play now requires a strict 24s measured AVPlayer buffer before autoplay and configures the initial Direct Play forward-buffer target to 24s.
- Latest validation after iOS Direct Play micro-stall buffer gate: targeted red tests failed before implementation and now pass; focused playback/orientation suite passed; `xcodegen generate`, iOS `ReelFin` build, tvOS `ReelFinTV` build, lightweight player E2E passed with artifacts `.artifacts/player-e2e/20260426-222115`; `git diff --check` passed.
- Deepened the Detail-page startup preheat for high-bitrate iOS progressive Direct Play. Instead of a fixed 2 MiB probe, the warmup now samples up to 12 MiB around the resume byte range, caps the request at the known file end, logs `reason=directplay_range_deep`, and still relies on measured AVPlayer buffer before autoplay.
- Fixed the iOS Play/Resume landscape transition artifact shown in `IMG_3565.png`. Detail/Home no longer change the orientation mask or request landscape geometry before presenting the full-screen player; `PlayerView` requests landscape only after the black/player surface is mounted, so the Detail card is no longer rotated/scaled over a black landscape canvas during the handoff.
- Fixed the follow-up Direct Play resume deadlock from the `resume=1590.1s` log. The old path deferred the initial seek while the item was not ready, but the only deferred seek executor ran after first-frame, while first-frame was also blocked until resume was satisfied. `AVPlayer` could therefore advance from `0s` while the pending resume target stayed at `1590s`. Direct Play now applies the pending resume seek on `AVPlayerItem.status == .readyToPlay`, verifies the current time is within tolerance, and blocks unsafe autoplay if the target is still not satisfied.
- Latest validation after the resume-deadlock fix: targeted red test failed before implementation and now passes; the native Direct Play integration test proves a local progressive `stream` seeks to the resume target before autoplay; focused playback/native/resume suites passed; `xcodegen generate`, iOS `ReelFin` build, tvOS `ReelFinTV` build, and `scripts/run_reelfin_player_e2e.sh --loops 2 --sample-size 4 --skip-ui --skip-tvos` passed with artifacts `.artifacts/player-e2e/20260426-232715`. The live UI smoke is intentionally not counted as player proof because it is still blocked by UI automation reliability before playback.
- Fixed the follow-up paused-start regression from the `session=2050da6b-50DCCF` log. The resume seek now landed correctly (`phase=item_ready ... satisfied=true`) and AVKit displayed the first frame at `currentTime=1590.417`, but the 24s paused readiness gate kept waiting for measured `loadedTimeRanges`, timed out at `buffered=4.6`, and then called `block_autoplay`, pausing a session that was already visually ready. The readiness gate now treats `first-frame + readyToPlay + resume target satisfied` as startup-ready evidence and returns before the timeout can block autoplay.
- Latest validation after the paused-start fix: the targeted red test failed before implementation and now passes; focused playback/native/resume/startup tests passed; `xcodegen generate`, iOS `ReelFin` simulator build, tvOS `ReelFinTV` simulator build, and `scripts/run_reelfin_player_e2e.sh --loops 1 --sample-size 4 --skip-ui --skip-tvos` passed with artifacts `.artifacts/player-e2e/20260427-205533`.
- Rebuilt the iOS Apple-native Direct Play contract after the post-first-frame `AVFoundationErrorDomain -11819` logs. The root issue was no longer resume or server throughput: the session had a valid first frame and resume seek, then the current branch suppressed playback-failure recovery after first frame, leaving a failed Direct Play `AVPlayerItem` dead. Direct Play rules now live in `DirectPlaySessionPolicy`, post-first-frame Direct Play item failures are allowed to use bounded same-route recovery, and MP4/MOV original URL construction uses `/stream.mp4` up front instead of a late URL rewrite.
- Added an explicit `PlaybackStartPosition`: the primary Detail action now sends `.beginning` when the UI label is `Play`, so a watched/near-finished item with stale Jellyfin progress cannot accidentally resume at `1590s`; `Resume` still uses the best server/local progress. The player presentation handoff keeps the Detail scene orientation stable until `PlayerView` is mounted, avoiding the rotated Detail-card artifact during the full-screen transition.
- Latest validation after the clean Direct Play reset: targeted red tests failed before implementation and now pass; focused playback/native/detail/orientation suite passed 128 tests; `scripts/run_reelfin_player_e2e.sh --skip-ui --skip-tvos --loops 1 --sample-size 4` passed with artifacts `.artifacts/player-e2e/20260427-211642` (`4/4` item probes, `4/4` benchmarks, `3/3` live probe, `69/69` deterministic tests, runtime log cleanliness pass); tvOS `ReelFinTV` simulator build passed.
- Added iOS high-risk progressive Direct Play preemption for auto quality. The `2050da6b` runtime now logs `playback.directplay.preemptive_fallback reason=ios_high_risk_progressive_directplay`, selects `route=Transcode (HLS) profile=forceH264Transcode`, and starts the real Jellyfin item without app-level stall or recovery markers.
- Latest validation after iOS preemptive HLS fallback: targeted red tests failed before implementation and now pass; `PlaybackEngineTests` completed 515 tests with 512 passed, 3 skipped, and 0 failures; XcodeBuildMCP `build_run_sim` succeeded on iPhone 17 Pro iOS 26.0; tvOS `ReelFinTV` simulator build passed; Computer Use simulator playback produced three different frames over roughly one minute and the redacted runtime log at `.artifacts/manual-player-debug/20260427-final-224605/runtime.redacted.log` contains no real `MEDIA_PLAYBACK_STALL`, `Playback stalled`, timeout, watchdog, route-guard block, or AVPlayer failure markers.
- Fixed the follow-up HLS resume-start mismatch from the iOS logs. The Detail button and playback plan could report `resume=...`, but the final normalized HLS transcode/remux URL loaded by AVPlayer could still omit `StartTimeTicks`, allowing Jellyfin to build a zero-second playlist. Non-direct server routes now append `StartTimeTicks` on the final asset URL before API-key injection, while Direct Play/native routes keep client-side resume behavior.
- Latest validation after the HLS resume URL fix: targeted red test failed before implementation and now passes; focused route/policy/session tests passed 162 tests; full `PlaybackEngineTests` passed 523 tests with 3 skips and 0 failures after stabilizing the concurrent mock repository as an actor; `scripts/run_reelfin_player_e2e.sh --loops 1 --sample-size 4 --skip-tvos` passed with artifacts `.artifacts/player-e2e/20260428-194046` (`4/4` explicit probes, `4/4` original-stream benchmarks, `3/3` live playback probes, `71/71` deterministic player tests, live iOS UI smoke, runtime log cleanliness pass).
- Superseded the previous HLS resume URL behavior after the `NSURLErrorDomain -1008` regression. Resume now stays in the Jellyfin PlaybackInfo request; the final HLS master URL, pinned variant URL, and AVPlayer asset URL strip `StartTimeTicks`/`StartTime` so segment URLs remain valid. If Jellyfin returns a server-offset stream, the player detects it from item duration and maps UI progress to the absolute movie time; otherwise it performs the normal client resume seek.
