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

### M30
- Status: completed
- Objective: make tvOS progressive Direct Play start immediately from the native Apple player path.
- Scope: `PlaybackStartupReadinessPolicy`, `DirectPlaySessionPolicy`, `PlaybackSessionController`, AVKit ready-display observer tests, native sample-buffer cancellation guards
- Acceptance:
  - tvOS MP4/MOV Direct Play no longer creates a startup readiness gate or range preheat requirement
  - high-bitrate/premium tvOS progressive Direct Play keeps the default fast buffer policy instead of forcing `24s` and `automaticallyWaitsToMinimizeStalling`
  - resumed tvOS MP4/MOV Direct Play primes the resume seek before autoplay instead of letting AVPlayer advance from `0s`
  - post-first-frame tvOS MP4/MOV Direct Play no longer applies the adaptive `24s`/`90s` caching ramp to progressive remote files
  - AVPlayer `waitingToPlayAtSpecifiedRate` preserves the app's active playback intent instead of reporting a user pause
  - post-first-frame tvOS Direct Play stalls keep the current item, avoid same-route reloads, avoid buffer target growth, and keep `automaticallyWaitsToMinimizeStalling` off
  - Detail warmup may still issue an opportunistic tvOS resume range preheat and consume that evidence for `play_ready`, but playback startup does not block on it
  - AVKit `readyForDisplay` signals that arrive before item readiness are rechecked when the item becomes ready
  - native sample-buffer async work is generation-guarded so stale MP4/Matroska tasks cannot publish or render after reload/stop
- Validation: targeted red/green playback policy, warmup, detail readiness, playback-state, adaptive-caching, and post-start stall tests; focused native player configuration tests; `xcodegen generate`; `ReelFinTV` build/test; and `scripts/run_reelfin_player_e2e.sh --skip-ui --loops 1 --sample-size 4 --max-failures 1` passed with artifacts `.artifacts/player-e2e/20260503-110443`.

### M31
- Status: completed
- Objective: rollback post-start Direct Play fallback behavior and keep visible playback on the original Direct Play item.
- Scope: `DirectPlaySessionPolicy`, `PlaybackSessionController`, `PlaybackCoordinator`, `StartupFailureReason`, playback policy/route-guard tests
- Acceptance:
  - once Direct Play has rendered a first frame, `directplay_poststart_stall` cannot trigger profile fallback, HLS/transcode fallback, same-route item reload, or stored transcode pinning
  - post-first-frame Direct Play stalls keep the current `AVPlayerItem`, reassert play intent, and let AVPlayer re-buffer the same progressive stream
  - tvOS post-start Direct Play stalls grow the requested forward-buffer target dynamically: `24s`, `60s`, `120s`, then `240s` for repeated stalls
  - post-start stall rebuffering enables `automaticallyWaitsToMinimizeStalling` after playback is already visible, preserving fast startup while prioritizing continuity after a stall
  - explicit native coordinator fallback is still allowed for decode failures like `audio_only_no_video`, but `directplay_poststart_stall` is blocked at the coordinator guard
- Validation: targeted playback and route-guard tests passed; `xcodegen generate` passed; `ReelFinTV` simulator build passed; live player E2E passed with artifacts `.artifacts/player-e2e/20260503-114654` (`4/4` explicit probes, resume reporting, `4/4` original-stream benchmarks, `3/3` live playback probes, `74/74` deterministic player tests, clean runtime-log scan).

### M32
- Status: completed
- Objective: make playback quality-first and measured-original-first without turning startup into a long network test.
- Scope: `DirectPlayStartupPolicy`, `PlaybackServerNetworkBaseline`, `PlaybackWarmupManager`, `PlaybackSessionController`, Home/Library warmup
- Acceptance:
  - foreground warmup can collect a single-flight authenticated server Range baseline with a short TTL and no sensitive URL/token logging
  - item-specific resume preheat remains stronger evidence than a global server baseline
  - high-bitrate progressive Direct Play uses fast startup when fresh measured baseline/preheat has large headroom, guarded startup when evidence is stale or absent, and blocks only when fresh item/server evidence is actually weak
  - Home and Library warmup pass resume/runtime context so focused or visible items can preheat the same startup bucket as playback
  - post-first-frame Direct Play stalls keep the current item, increase buffering policy, and mark the item route fragile only after repeated measured stalls so the next start requires stronger item-specific proof
- Validation: targeted red/green Direct Play startup and warmup tests passed; focused playback/native suite passed 211 tests; `xcodegen generate`, iOS `ReelFin` simulator build, tvOS `ReelFinTV` simulator build, and `git diff --check` passed; fast live Jellyfin E2E passed with artifacts `.artifacts/player-e2e/20260505-100500` (`4/4` explicit probes, resume reporting, `4/4` original-stream benchmarks, `4/4` live playback probes, `76/76` deterministic tests, clean runtime-log scan; UI and tvOS runner steps skipped by the fast variant).

### M33
- Status: completed
- Objective: add a dynamic original-media cache that can absorb network drops without lowering quality first.
- Scope: `PlaybackEngine` media gateway/cache store, Direct Play AVPlayer gateway routing, native byte source cache, Settings media-cache mode
- Acceptance:
  - `PlaybackMediaCachePolicy` chooses startup, steady, deep, complete, or paused cache phases from platform, route, headroom, storage, network cost, and cache mode
  - media payload ranges are stored in `Caches` with atomic `.part` writes, persistent TTL/LRU metadata, server/user scope removal, and active-item protection
  - route signatures ignore sensitive query/header values so raw or hashed API keys/tokens are not persisted in cache identity
  - Direct Play original can be served through a local `127.0.0.1` Range gateway with opaque session URLs and private remote headers
  - Direct Play gateway responses write through to cache and schedule bounded ahead prefetch from `PlaybackMediaCachePolicy`
  - tvOS automatic mode uses the local gateway for Apple-compatible Direct Play originals; iOS uses it for high-bitrate, resumed, or already cached originals
  - native sample-buffer playback reads remote originals through the same persistent byte cache when media cache is not Off
  - Settings exposes `Media Cache` as Automatic, Reduced, or Off plus a clear-cache action
- Validation: targeted cache/gateway/settings tests passed, including the red/green gateway prefetch test; `xcodegen generate`, iOS `ReelFin` build, tvOS `ReelFinTV` build, and `git diff --check` passed; fast live Jellyfin E2E passed with artifacts `.artifacts/player-e2e/20260505-122924` (`4/4` explicit probes, resume reporting, `4/4` original-stream benchmarks, `4/4` live playback probes, `76/76` deterministic tests, clean fatal-log scan; UI and tvOS runner steps skipped by the fast variant).

### M34
- Status: completed
- Objective: prevent stale Home enrichment snapshots from overwriting newer pagination and user state.
- Scope: `HomeViewModel`, Home action/enrichment tests
- Acceptance:
  - the current feed remains authoritative for row structure, item membership/order, pagination results, and user-controlled state
  - enrichment applies only `seriesName` and `seriesPosterTag` values that actually changed during processing for the same item ID
  - processed featured items fill a fallback only when both the source and current featured collections are empty
  - the regression test controls enrichment completion with a continuation and contains no timing sleep or retry
- Validation: the deterministic RED lost 3 paginated items and current favorite state; after the fix the regression passed `100/100` iterations without retry, both Home view-model test classes passed `16/16`, isolated XcodeGen generation succeeded, and the iOS `ReelFin` simulator build passed.

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

- Home stale-enrichment regression: passed `100/100` controlled iterations without retry; pre-fix RED reproduced 20 items instead of 23 and lost current favorite state.
- `HomeViewModelActionTests` plus `HomeViewModelFeedEnrichmentTests`: passed, 16 tests.
- isolated `xcodegen generate` and iOS `ReelFin` simulator build: passed without modifying the worktree's existing scheme changes.
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
- Added a native player surface preference for iOS and tvOS settings. The default remains "Direct Play when possible": Apple-compatible MP4/MOV originals short-circuit to AVKit Direct Play, while non-Apple originals use the custom sample-buffer player. The new "Always Custom Player" mode keeps native original-file playback enabled but bypasses AVKit Direct Play and routes compatible originals through the custom `AVSampleBufferDisplayLayer` path instead; warmup will not reuse Apple-native Direct Play selections in that mode.
- Latest validation after custom-player force option: targeted red tests failed before implementation and now pass; focused config/routing/settings tests passed 21 tests; focused warmup/native-session/reload tests passed 89 tests; `xcodegen generate`, iOS `ReelFin` simulator build, tvOS `ReelFinTV` simulator build, and `git diff --check` passed.
- Fixed the follow-up runtime/UI issue from the iOS `2050da6b` logs. `Always Custom Player` now writes a dedicated runtime surface preference immediately, `Off` explicitly disables the runtime native player even when older saved config enables it, DEBUG launch migration respects the stored choice after the current marker is applied, `applyingRuntimeOverride()` reads both runtime keys, and iOS/tvOS settings expose one `Native Playback` mode instead of a separate native toggle plus a second native mode control.
- Latest validation after runtime custom-player persistence: targeted red config/settings/session tests failed before implementation and now pass; the focused config/routing/settings suite passed 22 tests and confirmed `surfacePreference=customPlayer` routes compatible MP4 originals to `nativeplayer.sampleBuffer.route.selected` with no `AVPlayerItem`; focused native controller/route guard/warmup/reload tests passed 104 tests; `xcodegen generate`, iOS `ReelFin` build, tvOS `ReelFinTV` build, and `git diff --check` passed.
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
- Replaced the metadata-only iOS high-risk Direct Play preemption with a measured original-first startup policy. High-bitrate progressive Direct Play now runs warmup/inline Range preheat, keeps Direct Play when network headroom is healthy, uses short guarded startup windows when headroom is usable, and falls back to a server profile only when preheat is missing or below the source bitrate headroom threshold.
- Latest validation after dynamic original-first Direct Play policy: targeted red tests failed before implementation and now pass; focused playback/native startup tests passed 202 tests; `xcodegen generate`, iOS `ReelFin` simulator build, and tvOS `ReelFinTV` simulator build passed; lightweight live player E2E passed with artifacts `.artifacts/player-e2e/20260504-213021` (`4/4` explicit probes, resume reporting, `4/4` original-stream benchmarks, `4/4` live playback probes, `76/76` deterministic tests, clean fatal-log scan; UI and tvOS runner steps intentionally skipped by the fast variant).

## Home Recently Released TV - 2026-05-03

- Fixed the Home "Recently Released TV Shows" rail ordering for iOS/tvOS. The rail now uses recent episode `PremiereDate` signals, ignores incremental sync cutoffs for that rail, filters missing/unaired plus future or undated episodes before resolving parent series, and keeps the other Home rails unchanged.
- Fixed the Home cache overwrite regression where an incremental sync with only `Continue Watching` and `Recently Released TV Shows` could replace the cached five-row Home feed. Incremental Home sync now treats empty or missing catalog rows as degraded, fetches a full feed before saving, and keeps cached rows if the full-feed fallback fails.
- Fixed the Home UI row filtering regression where empty canonical rows were dropped before rendering, leaving only `Continue Watching` and `Recently Released TV Shows` visible even when the cached feed contained all five rows.
- Latest validation after Home correction: targeted red tests failed first for future/undated TV release ordering, incremental Home cache overwrite, and empty canonical row filtering, then passed; combined focused Home/Jellyfin tests passed 13 tests; `xcodegen generate` passed; `ReelFinTV` simulator build passed; `git diff --check` passed for the touched files.

## Playback Quality Guarantees - 2026-05-07

- Added route guarantees for Direct Original, video-copy remux, audio-only transcode, video transcode, HDR/Dolby Vision preservation, and startup class. Coordinator and session diagnostics now carry the selected route summary, redacted final URL, original codecs/container, DV class, startup timing, health state, and gateway state.
- Rebalanced routing away from silent 4K HDR/Dolby Vision downgrade paths. Server-default MKV HEVC/HDR/DV now keeps video-copy fMP4/HLS remux when Jellyfin exposes copy evidence, NativeBridge failure falls back to server remux first, and automatic recovery filters video-transcode profiles for 4K HDR/DV unless a future UI choice explicitly opts into lower quality.
- Added public fallback recommendation state for destructive route attempts, weak bandwidth/repeated stalls, and subtitle burn-in. PGS/VobSub and risky ASS/SSA subtitles on 4K HDR/DV now produce keep-original vs compatible-playback options instead of silently burning subtitles into video.
- Added `PlaybackStartupPolicy` and `PlaybackHealthMonitor`: direct/original routes use short forward buffers and guarded `playImmediately`, HLS remux/video transcode use larger buffers, startup traces record TTFF phases, and stall/bandwidth diagnostics compute observed vs required bitrate when access-log data is available.
- Improved LocalMediaGateway correctness and diagnostics by preserving upstream content type, validating invalid/open/suffix ranges, returning 416 with `Content-Range: bytes */total`, tracking throughput, and keeping exposed/logged URLs redacted.
- Validation in progress for this branch: `xcodegen generate` passed; focused playback guarantees/startup/health/policy/decision/gateway tests passed 78 tests. Full iOS/tvOS gates are tracked in `OPTIMIZATION_AUDIT.md`.

## iOS Direct Play Startup Stall - 2026-05-08

- Fixed the iOS `2050da6b` Direct Play cut where AVKit accepted startup from first-frame evidence at `currentTime=0` with only about 2s of measured buffer, then stalled around 10s. Fresh high-bitrate progressive Direct Play now requires a strict 24s measured AVPlayer buffer, uses a 30s startup timeout without timeout-start fallback, disables the first-frame shortcut, and sets the initial iOS forward-buffer target to 24s.
- Latest validation after strict iOS Direct Play startup gate: targeted red test failed before implementation and now passes; focused Direct Play startup/readiness/session tests passed 30 tests; full `PlaybackSessionControllerTrackReloadTests` passed 87 tests; `xcodegen generate`, iOS `ReelFin` build, tvOS `ReelFinTV` build, and `git diff --check` passed.
- Follow-up fix for the paused autoplay/audio drop logs: measured-headroom Direct Play skips wait for the current `AVPlayerItem` to reach `readyToPlay`, but iPhone high-bitrate progressive Direct Play can no longer convert synthetic preheat/server-baseline headroom into a fast start. It must still satisfy the measured AVPlayer buffer gate, and a visible resume frame no longer bypasses that gate.
- iOS post-start Direct Play stalls now pause the current item and wait for measured AVPlayer rebuffer before resuming instead of immediately calling `play()` again. tvOS keeps the existing keep-current-item behavior with conservative waiting.
- Latest validation after the follow-up: new regression tests for guarded iPhone headroom, first-frame resume bypass, and iOS post-start measured rebuffer passed; focused Direct Play startup/readiness/session tests passed 120 tests.

## macOS Catalyst Bring-Up And Live Player Validation - 2026-05-09

- ReelFin now has a generated Mac Catalyst build path from `project.yml`, with the app bundle identifier and target device family scoped to the macOS SDK and a local `scripts/run_reelfin_macos.sh` build/run helper.
- Root navigation uses an explicit platform policy so Mac Catalyst gets a dedicated Mac shell instead of reusing the iPad split layout, while screenshot mode and compact iPhone layouts keep their existing behavior.
- The Mac shell uses a native sidebar-detail structure with scene-restored selection, toolbar refresh/sidebar controls, and Command-menu shortcuts for Home, Library, Settings, and Refresh.
- Follow-up live UI evidence exposed a Direct Play readiness timeout after AVKit had already produced a resumed first frame. Startup readiness can now accept first-frame evidence for Direct Play only when playback is actively requested, the item is ready, and the pending resume target is satisfied.
- Latest validation: `xcodegen generate`, Mac Catalyst build/run verification, focused Mac Catalyst layout/readiness tests, live player E2E with artifacts `.artifacts/player-e2e/20260509-110718`, tvOS build gate, and runtime-log cleanliness passed. Mac Catalyst XCUITest UI traversal is still blocked before app interaction by Xcode's `Timed out while enabling automation mode`.
- 2026-05-10 Mac shell validation: focused `RootDesktopLayoutPolicyTests` passed, `scripts/run_reelfin_macos.sh --verify` built and launched `ReelFin=RUNNING`, and `ReelFinTV` simulator build passed after the shared root change.

## tvOS Player Chrome And Remote Ownership - 2026-07-11

- CustomPlayer and NativePlayer now share the Apple-style bottom metadata/timeline/action composition. The normal action set is Audio, Sous-titres, and Vidéo; Vidéo opens a real route/quality panel and track choices use the compact right-side glass panel.
- ReelFin is the sole tvOS remote owner: inline AVKit controls and UIKit press interception are disabled, one SwiftUI command handles Play/Pause, Select shows/hides chrome, Left rewinds 10 seconds, Right advances 30 seconds, and Menu closes panel, then chrome, then player.
- Horizontal seeks are clamped and coalesced before reaching the active engine. Focus returns through state tokens and task yielding, never fixed-delay focus sleeps.
- Validation: policy/layout tests were red before implementation; 51 focused tests passed after implementation, iOS 27 and tvOS 27 simulator builds passed, `xcodegen generate` passed, and the authenticated tvOS simulator retained its Jellyfin session during update-install. Full XCUIRemote journeys remain Task 5.
- Liquid Glass follow-up: both tvOS playback routes now match the native reference hierarchy with an 80-point inset, 360-point bottom gradient, episode/title row, three availability-filtered circular Subtitles/Audio/Video controls, full-width timeline with playhead-aligned elapsed time, and Info/Détails/Continuer glass pills. Info and Video expose playback quality/route; Détails exposes only honest Jellyfin item metadata; Continuer resumes paused playback and hides chrome.
- The track picker now adapts the simple iOS list model to tvOS instead of presenting an oversized dark card: a compact 460-point right-side Liquid Glass panel, 58-point rows, structured title/metadata, a separate checkmark for the selected track, and a restrained translucent focus state. Every rendered control has a real action; unavailable Audio/Subtitles actions are omitted.
- Final evidence: 64 focused player/layout/persistence tests passed in the independent review, iOS 27 and tvOS 27 builds passed after `xcodegen generate`, and authenticated Star City S1E1 XCUIRemote journeys passed track changes, panels, focus restoration, paused Continuer, seek to zero, forward seek, and ten alternating Continuer/Recommencer launches. Final captures are `/tmp/ReelFinFB30FocusedAttachments/53CBEA74-DB57-43BC-A243-E3CBAF054B5F.png` and `/tmp/ReelFinTrackPickerAttachments2/86A04C6D-B55D-49EB-98D9-093BD6657E9C.png`.
- Hardened live-suite follow-up: the Jellyfin tvOS journey is now hermetic and opt-in through the redacted alias `star-city-s1e1`; XCTest contains no credentials, server URL, user/item IDs, or network authentication. Resolution happens inside the already-authenticated DEBUG tvOS app, and both CustomPlayer reporting and legacy/native progress persistence are disabled for that isolated run.
- Playback proof is route-specific and non-latching: native audio requires samples accepted by `AVSampleBufferAudioRenderer`, custom audio requires an AVFoundation-selected audible option plus a fresh advancing clock, and advancing evidence expires on pause/freeze/seek/generation reset. Continue and Restart assert actual first positions, panels perform real audio/subtitle changes, and the reliability loop can never run fewer than ten iterations.
- Star City S1E1 exposed an alternate-container metadata bug: codec-less same-ID subtitle placeholders on the preferred MP4 source masked the real SRT tracks on its MKV twin. The merge now upgrades incomplete placeholders while retaining the twin source ID needed by Jellyfin's subtitle delivery URL.
- The final tvOS chrome uses availability-filtered native Glass buttons and an explicit remote focus graph across Subtitles/Audio/Video, timeline, Info, Détails, and Continuer. Closing a panel restores its originating control through a stable focus scope plus a latest-wins request token; directional navigation refreshes chrome visibility instead of letting it disappear mid-navigation.
- Final authenticated Apple TV 4K (3rd generation) tvOS 27 simulator validation on Star City S1E1 passed: tracks/panels/focus/paused Continue in 55.857s, Continue/pause/resume/seek-to-zero/forward in 46.498s, and 10 alternating Continue/Restart launches in 135.492s. Final focused coverage passed 61 tests; iOS/tvOS builds, `xcodegen generate`, `git diff --check`, and default opt-out execution (3 skipped, 0 failures) passed.
- Task 5 final AVKit-menu proof adds exact DEBUG tvOS markers for Audio, Subtitles root, Language, and Style plus kept screenshots named `avkit-audio`, `avkit-subtitles-root`, `avkit-language`, and `avkit-style`. The authenticated Star City S1E1 path changes one real subtitle language, both background styles, and one real audio track only after focus is established; every selection re-proves `playing`, fresh advancement, increasing playback time, and no `player_error`.
- Strict capture review rejected two intermediate states: Language initially had no checkmark while subtitles were Off, and the fixed 520-point ScrollView left a large dark empty area below short menus. Language now checks the retained activatable preference without enabling subtitles, and deterministic content heights hug four Audio rows (278 points), two Style rows (138 points), and cap long lists at 520 points for scrolling. The final cards preserve width, radius, insets, typography, opacities, Liquid Glass transmission, contained gray focus, complete text, details, checks, and root chevrons.
- Final Task 5 evidence on Apple TV 4K (3rd generation) simulator `092D088B-6307-4EFB-AE53-2457C2EE7F1A`: 3/3 layout tests passed in 0.006s; the compact live menu journey passed in 96.697s; and the complete `ReelFinTV` gate passed 2/2 local tests plus 3/3 authenticated live journeys with zero failures. Final live durations were 96.235s (menus/tracks/panels/focus/paused Continue), 46.629s (pause/resume/seek-to-zero/forward), and 138.784s (10 alternating Continue/Restart cycles), with 281.649s for the live suite and 287.775s for `xcodebuild`.
- Final screenshots: Audio `/Users/flo/Documents/Projet/ReelFin/.artifacts/player-e2e/task5-avkit-compact-final-20260712/28B9B261-4401-4DE0-8A19-3BC752909037.png`; Subtitles root `/Users/flo/Documents/Projet/ReelFin/.artifacts/player-e2e/task5-avkit-compact-final-20260712/00DB0AAC-5F5F-4D1A-A3AB-187D467DC2B0.png`; Language `/Users/flo/Documents/Projet/ReelFin/.artifacts/player-e2e/task5-avkit-compact-final-20260712/88642741-3EA7-4F5C-A72E-C98BF28E5201.png`; Style `/Users/flo/Documents/Projet/ReelFin/.artifacts/player-e2e/task5-avkit-compact-final-20260712/F3760368-232E-4F65-AE2E-CF5E2D3EE86D.png`. `xcodegen generate` and `git diff --check` passed. Simulator evidence validates routing, accepted audio-renderer state, menus, focus, and continuity; it cannot prove audible speaker output, HDMI formats, HDR/Dolby Vision display-mode switching, tone mapping, or final panel luminance, which require compatible Apple TV/display hardware.

## Final Player Review Corrections - 2026-07-12

- Completed the adaptive Resume safety pass: resolve-only prewarm never retains or serves adaptive HLS, and Play resolves adaptive sources with the exact resume ticks.
- Replaced the process-wide resolver lock race with an actor-backed, identity-aware single-flight keyed by resume ticks and the non-logged authenticated server/user/session scope; concurrent callers share one resolve and session changes cannot reuse signed URLs or headers.
- Moved subtitle enable memory to the CustomPlayer/NativePlayer routes, restored only confirmed choices, and enforced remembered/selected -> Default/Défaut -> Forced/Forcé -> first precedence across menu reopen.
- Split sidecar pending and confirmed state, confirmed only after successful download/parse, and routed failure through the existing player error state without presenting the failed track as selected.
- Removed raw audio/subtitle IDs from selection logs and added a source scan covering IDs, URLs, headers, tokens, and API keys on those paths.
- Validation: the combined resolver/player/subtitle/menu/logging suite passed 238/238 on iPhone 17 Simulator 27.0; `xcodegen generate`, iOS `ReelFin` build, tvOS `ReelFinTV` build, and whitespace checks passed.

## tvOS Authenticated UX Proof And Performance Audit - 2026-07-12

- Added authenticated tvOS journeys for Home and Library focus travel, compact Resume choice focus/cancel behavior, Home/Library detail round trips, rapid double-Back handling, playback continuity, and the circular-scrub fallback contract.
- The live detail-return proof exposed two related Home focus defects: duplicate item IDs across shelves made focus restoration ambiguous, and the first Detail callback could rewrite a row return target to Hero. Row-qualified focus identities and source-preserving return state now restore the exact originating card without a transient Hero fallback canceling the handoff.
- Xcode 27 Device Hub exposes only cardinal remote controls, Select, Back, Home, and Play/Pause; it does not expose a clickpad/indirect-coordinate gesture. The authenticated journey therefore records circular input as unavailable and proves the safe idle fallback, while deterministic tests cover 100 circular scrub sessions plus -10/+30-second cardinal seeks and live-stream zero/forward seeking.
- Final verification passed with zero failures: 95/95 focused iOS tests in 0.158 seconds (4.155-second Xcode test operation), 2/2 local tvOS tests in 0.110 seconds (3.270-second Xcode test operation), and 8/8 authenticated live tvOS journeys in 384.118 seconds (387.680-second Xcode test operation). `xcodegen generate`, iOS `ReelFin`, tvOS `ReelFinTV`, and whitespace gates passed; standalone build durations were not captured in their logs.
- Exported screenshots in `.artifacts/player-e2e/task6/tvos-live-final-green-attachments` show fully visible focused Home and Library cards, a centered and unclipped compact Resume choice, and continuous dim/scale/zoom detail transitions without a hard black cut.
- Performance probes completed: the player UI probe executed zero successful checks because both selected tests were credential-skipped (2/2 skipped, 79.466-second test suite; outer command duration not captured in the log). Compensating authenticated tvOS journeys prove the live UX, while the playback QA loop passed 970 PlaybackEngine tests with ten expected skips in 411.725 seconds plus six ImageCache tests in 0.922 seconds; its outer command duration was not captured in the log. The standalone tvOS profile could not start because it requires credentials intentionally not exported from the preserved signed-in simulator container.
- Simulator evidence validates navigation, routing, accepted renderer state, metadata, and an advancing playback clock. Audible HDMI output, negotiated audio formats, HDR/Dolby Vision display-mode switching, tone mapping, luminance, and physical clickpad feel remain hardware-only validation items.

## tvOS Authenticated Focus Review Follow-up - 2026-07-12

- Mandatory authenticated Home/Library focus acquisition now hard-fails when cards exist but focus cannot be acquired; only genuinely unavailable opt-in live setup remains skippable.
- Added a DEBUG tvOS automation-only UIKit accessibility marker, `tv_home_focus_transition_count`. It exposes only a monotonically increasing count, never an item ID or media value, and the mutation itself is disabled outside the automation policy.
- The authenticated Home move proof reads the settled count around exactly one Down event and requires a delta of exactly one. The focused Home/Library/Home-Back/Library-Back suite passed 3/3 in 63.011 seconds (74.034-second Xcode test operation), and rapid Back passed 1/1 in 11.225 seconds (14.864-second Xcode test operation).
- The preparation screenshot is now captured only after the preparation accessibility marker exists. Focus evidence policy/counter and source contracts followed RED/GREEN and passed 2/2 in 0.024 seconds (3.931-second Xcode test operation). The final tvOS build succeeded; its duration was not emitted or captured.

## tvOS UX Polish Final Review Fixes - 2026-07-12

- Home Detail return state now retains its immutable presentation origin and rail snapshot. Carousel changes resolve inside that Hero or row only; duplicated media cannot jump rails, and a removed target falls back to the nearest surviving item from the same presentation rail.
- tvOS focus motion uses the approved 0.28-second spring with 0.80 bounce, while Reduce Motion uses a 0.18-second ease-out. Library activation is capped at 1.025. Resume choice spacing and question size are tokenized at 16 and 32 points.
- Final deterministic verification passed 38/38 TVUX/Home tests. `xcodegen generate` and the ReelFinTV build on `092D088B-6307-4EFB-AE53-2457C2EE7F1A` passed. The focused Home-to-Detail Back journey passed twice consecutively after one transient focus-restoration timeout; no existing UI test drives carousel neighbor changes, which remain covered by deterministic provenance tests.

## TestFlight Release Gate Follow-up - 2026-07-13

- Removed duplicate focus ownership from tvOS Home and Library cards. Each surface now derives styling, warmup callbacks, and restoration from exactly one parent-owned focus identity; Search keeps one local focus identity because it has no parent restoration binding.
- Fixed deep-row Home return cancellation. Automatic focus changes produced while a rail scrolls back into view no longer cancel the pending exact-card handoff; an actual Siri Remote move still cancels it through `onMoveCommand`, and coordinator ownership rejects stale completions.
- Hardened XCUI focus settling without weakening the final contract: one outgoing/incoming accessibility snapshot overlap is ignored, but three or more focused snapshots fail immediately and success still requires three consecutive unique observations.
- Release evidence passed on the preserved authenticated Apple TV 4K simulator: exact Home Detail return passed 5/5 consecutive iterations, then the complete `ReelFinTV` gate passed 2/2 local tests and 8/8 live Star City S1E1 journeys in 391.100 seconds with zero failures. The final live suite includes menus/tracks, resume choice, pause/resume, seek to zero/forward, Home/Library focus and Back, rapid Back, and ten alternating Continue/Restart launches.
- The iOS release gate also passed with zero failures: 975 PlaybackEngine tests (10 expected skips), 6 ImageCache tests, 45 JellyfinAPI tests, and 17 UI tests (6 expected live-fixture skips). A deterministic Jellyfin 401 defect found by that gate now invalidates only the rejected session token and cannot erase a newer reauthenticated session.

## Unified iPhone And Apple TV Release Boundary - 2026-07-13

- The unified release keeps one App Store record through the unchanged `com.reelfin.app` bundle identifier on both applications while restricting the generated binaries to iPhone and Apple TV. The iOS app explicitly supports only `iphoneos iphonesimulator`, disables Mac Catalyst plus Designed for iPhone/iPad compatibility on macOS and visionOS, and retains device family `1`; the tvOS app explicitly supports only `appletvos appletvsimulator` and retains device family `3`.
- Release preflight now rejects any repo-wide `SUPPORTS_MACCATALYST: YES` declaration and requires the explicit compatibility and SDK boundaries. `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodegen generate` succeeded, and `scripts/preflight_testflight_release.sh` passed every assertion.
- Effective Release build settings confirmed version `0.1.1`, build `12`, and `com.reelfin.app` for both schemes. `ReelFin` reported iPhone SDKs, family `1`, and all three compatibility flags `NO`; `ReelFinTV` reported Apple TV SDKs and family `3`.

## tvOS TestFlight Authenticated Launch Crash - 2026-07-13

- Reproduced the TestFlight launch-close failure with a normally signed, optimized `Release-appletvsimulator` build installed over the preserved authenticated Apple TV simulator state. The process aborted about three seconds after launch while the cached Home feed was resolving episode series metadata from the live Jellyfin server.
- The symbolicated crash ended in `__cxa_pure_virtual` from `swift::AsyncTask::completeFuture`. A canceled Home enrichment generation still owned `withTaskGroup` children while the replacement generation shared the same series lookup; Jellyfin response decoding then completed a child future from the canceled generation.
- Removed child-task fan-out only from this secondary Home metadata enrichment. Series lookups now run sequentially with cancellation checks before and after every request, so canceled generations cannot apply partial results or complete the crashed child-future path. Cached Home rows still paint immediately; the tradeoff is slower background series-name/poster enrichment when many parents are uncached.
- Added a regression contract that failed before the correction with two simultaneous series lookups and passes after it with a maximum concurrency of one. The complete Home action suite passed 9/9. Final gates passed 979 PlaybackEngine tests, 6 ImageCache tests, 45 JellyfinAPI tests, 17 iOS UI tests, 2 local tvOS tests, and all 8 authenticated tvOS journeys with zero failures; expected fixture-dependent skips remain explicit.
- The signed optimized tvOS `0.1.1 (13)` build retained the Jellyfin session, rendered the live Home feed, survived 10/10 terminate/relaunch cycles plus a 76-second final survival check, and produced zero new crash reports. The standard E2E runner separately proved 4/4 original streams, 4/4 original benchmarks, and resume reporting; its HLS segment probe exposed a server-side Jellyfin `HTTP 500` on 10/10 transcode segments, while its Xcode 27 UI environment propagation and loopback-log scanner remained non-authoritative. Those runner limitations are recorded rather than counted as passes.
- Build `13` is the corrected Apple TV TestFlight train. Its signed archive and exported IPA passed bundle, platform, entitlement, and code-signature inspection; App Store Connect accepted it as `0.1.1 (13)`, Beta App Review approved it, and both the Internal Testers and External Testers groups contain the build. The existing public link remains `https://testflight.apple.com/join/TkVVXmU2`.

## Unified TestFlight Launch Hotfix - 2026-07-14

- Publish `0.1.2 (14)` to both iPhone and Apple TV under the existing App Store record. The release carries the authenticated Home enrichment lifetime fix that was absent from the iOS `0.1.1 (12)` binary and must be common to both platforms.
- Keep iOS navigation entirely system-native: Home and Settings remain contiguous primary tabs, with the `.search` role declared last so SwiftUI renders Search as the separate Liquid Glass control.
- Release gates require targeted launch/tab regressions, both simulator schemes, optimized signed install-over launches, and repeated iOS/tvOS relaunches. The preserved tvOS Jellyfin authentication must not be erased or replaced.
- tvOS focus no longer uses the former `0.80`-bounce spring. Home, Library, Search, Detail, episode cards, top navigation, and player controls use a 0.16-second non-overshooting focus transition; focused Home/Library artwork grows to 1.08–1.09 with static focused-only Liquid Glass surfaces.
- The tvOS top navigation mirrors the iPhone split hierarchy with Watch Now/Library in one glass rail and Search in its own circular glass surface. Home and Library release their outgoing focus before mounting Detail, Detail explicitly releases the global rail, and Play is the first focus target for normal and direct episode entry.
- Final simulator evidence: 33/33 focused deterministic tests passed; authenticated Home/Library Detail round trips passed 2/2 with Play focused without a Remote nudge; the Star City S1E1 playback journey passed focus, Continue, video/audio readiness, stable pause/resume, seek-to-zero, forward seek, and no player error. Final optimized `0.1.2 (14)` builds passed on both platforms and survived 10/10 install-over relaunches each without a new ReelFin crash report.

## Skip Intro Release Blocker - 2026-07-14

- Fixed marker delivery on both playback routes. Custom playback now validates, sorts, and immediately resolves newly fetched Jellyfin segments instead of waiting for its one-second transport monitor. The native SampleBuffer route now resolves markers from its own authoritative timeline rather than the inactive session `AVPlayer` clock.
- Added an actionable Liquid Glass Skip control to the SampleBuffer surface on iOS and tvOS. Seek markers are committed to the visible SampleBuffer renderer and synchronized back to the playback session; next-episode actions remain session-owned.
- Fixed tvOS focus ownership for transient Skip actions. Both player routes release the timeline and invisible Remote-input focus before focusing Skip, including when markers are already loaded at view presentation, then restore normal Remote ownership after the suggestion disappears.
- Deterministic coverage passes for immediate custom-marker publication, SampleBuffer seek routing, and SampleBuffer marker timeline updates. The authenticated Star City S1E1 journey restarts from the beginning, reaches the real Jellyfin Intro marker using Siri Remote seeks, focuses and activates Skip Intro, lands beyond the marker end, and re-proves advancing playback, video, audio, and no player error.
