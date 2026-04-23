# ReelFin Optimization Audit

## Measured Problems

1. Critical: launch path eagerly constructs the full production container before the root view can resolve auth state.
   Files: `ReelFinApp/App/ReelFinApp.swift`, `ReelFinApp/App/AppContainer.swift`, `ReelFinApp/AppTV/ReelFinTVApp.swift`, `ReelFinApp/AppTV/TVAppBootstrap.swift`
   Impact: longer cold launch and unnecessary logged-out spinner time.
   Fix: build a synchronous `LaunchSnapshot` from persisted settings and token state, and gate foreground sync on an active session.

2. High: authenticated Home first paint waits on `sync(.appLaunch)` even when cached content exists.
   Files: `ReelFinUI/Sources/ReelFinUI/Home/HomeViewModel.swift`
   Impact: slower warm launch and slower return-to-app responsiveness.
   Fix: publish cached Home immediately, keep sync as background enrichment.

3. High: Library search/filter/sort/pagination use multiple unowned tasks and can race.
   Files: `ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift`, `ReelFinUI/Sources/ReelFinUI/Library/LibraryViewModel.swift`
   Impact: stale grid results, extra UI churn, unnecessary repeated work.
   Fix: centralize criteria changes and pagination into one generation-based latest-wins load pipeline.

4. High: tvOS focus handoff currently includes fixed sleeps in the root shell and content-entry helpers.
   Files: `ReelFinUI/Sources/ReelFinUI/TV/TVRootShellView.swift`, `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`, `ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift`, `ReelFinUI/Sources/ReelFinUI/TV/TVSearchView.swift`
   Impact: visible focus latency and fragile navigation on Apple TV.
   Fix: notify readiness from content focus paths and shrink fixed-delay fallback windows.

5. Medium: speculative artwork warming on Home/Library/Detail primarily warms HTTP/server cache, not decoded image cache.
   Files: `JellyfinAPI/Sources/JellyfinAPI/JellyfinAPIClient.swift`, `ImageCache/Sources/ImageCache/DefaultImagePipeline.swift`, `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`, `ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift`, `ReelFinUI/Sources/ReelFinUI/Detail/DetailViewModel.swift`
   Impact: slower first render after navigation and extra decode churn during focus/scroll.
   Fix: route speculative artwork requests through `DefaultImagePipeline.prefetch(urls:)` and deduplicate candidate URLs.

6. Medium: non-selected iOS detail cards were still rendering the full hero backdrop path.
   Files: `ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift`
   Impact: extra artwork requests, decode work, blur cost, and carousel hitch risk while swiping.
   Fix: use a lighter preview-card artwork mode for non-selected cards and reserve the full cinematic background path for the active hero.

## Inferred Problems

1. High: `DetailViewModel` season and prepared-episode tasks can outlive the current selection.
   Files: `ReelFinUI/Sources/ReelFinUI/Detail/DetailViewModel.swift`
   Impact: stale progress or warmup state can land after a newer episode or season selection.
   Fix: introduce explicit season and episode selection tokens plus cancellable preparation tasks.

2. Medium: Home and Detail still have broad invalidation surfaces.
   Files: `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`, `ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift`
   Impact: unnecessary body recomputation during focus, scroll, and phased loading.
   Fix: split scroll and hydration state from the largest view roots in a follow-up milestone.

3. Medium: playback observer work still has lifecycle-owned-task gaps.
   Files: `PlaybackEngine/Sources/PlaybackEngine/PlaybackSessionController.swift`, `ReelFinUI/Sources/ReelFinUI/Player/NativePlayerViewController.swift`
   Impact: stale observer mutations after stop/reload remain possible.
   Fix: item-scoped observer guards and delayed validation ownership landed; keep pushing synthetic seek invalidation and remaining hot observer work into cancelable or session-scoped ownership.

4. Low: repo cleanup drift left obviously stale operational files behind.
   Files: `tasks/todo.md`, `scripts/export_marketing_screenshots.sh`
   Impact: misleading backlog state and broken maintenance entry points.
   Fix: remove files only when they are unreferenced or target already-deleted codepaths.

## Speculative Improvements

- Replace the dependency bag with narrower feature containers.
- Split `PlaybackSessionController` into lifecycle, route-planning, and reporting components.
- Unify image URL generation and speculative artwork policy behind a dedicated artwork service.

## Top 10 Ranked Fixes

1. `High-leverage architecture change` startup snapshot plus lazy heavy-service startup
2. `Quick win` gate foreground sync on authenticated session and fix UI-test reset ordering
3. `High-leverage architecture change` cached-first Home load independent from app-launch sync
4. `Quick win` Library latest-wins request ownership
5. `Medium refactor` Detail season and episode freshness tokens
6. `Medium refactor` narrower SwiftUI observing surfaces on Home and Detail
7. `Quick win` cheaper artwork for non-selected detail preview cards
8. `Quick win` tvOS content-ready focus handoff and test compile fix
9. `Medium refactor` playback observer lifecycle ownership
10. `Quick win` decoded-image speculative prefetch

## Implemented So Far

- Launch bootstrap now uses a synchronous `LaunchSnapshot` so persisted auth/onboarding state is available before `ReelFinRootView` starts async bootstrap.
- UI-test auth reset now runs before API session capture, and foreground sync is skipped when there is no active session.
- `HomeViewModel` now publishes cached/stale Home content before app-launch sync finishes and only treats launch as blocking when there is nothing renderable.
- `LibraryViewModel` now owns one generation-based latest-wins pipeline for reloads and pagination, with explicit task cancellation instead of overlapping ad hoc loads.
- `DetailViewModel` now uses season and episode freshness tokens plus owned warmup/progress tasks so stale async work cannot overwrite the current selection.
- Non-selected iOS detail carousel cards now use a lighter preview artwork path instead of paying the full hero-background cost for every card.
- tvOS focus handoff removed the largest fixed sleeps from root/search/library entry and reduced fallback delays in Home focus restoration.
- Speculative artwork warming now reaches `DefaultImagePipeline.prefetch(urls:)`, and both pipeline-level and API-level candidate URLs are deduplicated before work starts.
- tvOS live smoke tests no longer depend on unsupported `tap()` login flows; they compile and skip cleanly when the simulator lacks an authenticated session.
- `PlaybackSessionController` now cancels delayed validation, synthetic seek invalidation, and synthetic prefetch work on stop/reload, instead of letting stale delayed tasks drift across sessions.
- `NativePlayerViewController` no longer creates a new `Task` on every 150 ms trickplay preview tick.
- Removed stale repo artifacts that no longer had a valid backing workflow: `tasks/todo.md` and `scripts/export_marketing_screenshots.sh`.
- `PlaybackSessionController` now overlaps startup preheat with AVPlayer preparation and gates high-risk autoplay on bounded buffer readiness, reducing start-then-stall behavior without blocking HLS playlist startup behind byte-range probes.
- `DetailViewModel` now treats episode playback preparation as latest-wins, so stale progress or warmup selections cannot overwrite the active detail playback target.
- Added token-safe media cache keys and a durable `MediaGatewayIndex` so future player warmup and cache promotion work can reason about route, user/server scope, audio/subtitle choice, resume bucket, TTL, byte size, and LRU order without persisting raw credentials.
- Added `HLSSegmentDiskCache` as the first concrete media payload cache for playlists, init segments, and media segments, with hashed filenames, TTL expiry, LRU eviction, corrupt-index recovery, and sensitive-material regression tests.
- Added `scripts/run_zero_stall_validation.sh` as a repeatable validation runner for XcodeGen, iOS build, tvOS build, startup/detail tests, and App Store screenshot tests.
- High-bitrate iOS DirectPlay startup now keeps AVPlayer paused through replacement, seek, bounded readiness gating, and video preroll, refuses timeout-based start when measured buffer is still empty, uses a 12s no-stall buffer target instead of the 30s startup-heavy target, and only marks first frame after a real video pixel buffer when video output is attached.
- Startup DirectPlay stalls, readiness timeouts, and video-preroll failures now preserve resume ticks and recover through direct-route-disabled HLS/transcode profiles instead of replaying the same progressive DirectPlay path that just failed.
- The latest log regression (`resume=1077.5s` followed by fallback `resume=none` and first frame near 2s) is covered by tests that force a DirectPlay-capable MOV/MP4 source through recovery and assert `StartTimeTicks` plus an H.264 transcode route.
- Detail-page playback warmup now passes resume/runtime/platform context into `PlaybackWarmupManager`, which deduplicates startup media-byte preheats by route, platform, and resume bucket; playback startup uses the same preheater path so a warmed detail page can avoid repeating untracked probes.
- Series detail warmup now resolves Jellyfin Next Up before loading episodes, selects the matching season when the next episode is in a later season, and only falls back to first unplayed/first episode when the server has no Next Up target.
- tvOS Home, Detail, Library, Search, and top navigation now use native no-chrome `Button` activation for selectable focus surfaces instead of custom focusable views with tap gestures; Detail row-up navigation also scrolls the target section into view before applying the focus handoff.
- The earlier strict sparse-buffer fallback path is superseded because it caused false tvOS progressive Direct Play startup timeouts and transcode restarts before the first frame.
- Detail-page warmup no longer marks progressive Direct Play as fully ready from disposable URLSession range-probe bytes; the UI signal is reserved for startup paths with cache/readiness evidence AVPlayer can actually consume.
- Earlier Direct Play startup tuning prioritized sparse telemetry and skipped blocking tvOS video-preroll recovery; the post-first-frame stall suppression from that pass is superseded by the latest cut-after-start fix below.
- The previous tvOS Direct Play no-cut rule favored a single uninterrupted progressive item; the latest `MEDIA_PLAYBACK_STALL` log showed that a bounded post-start fallback is safer for visible playback continuity.
- Detail-page background playback warmup no longer drives the blocking `Preparing` state or disables tvOS Play focus; Direct Play preheat timeouts can fail silently without trapping the Detail page.
- The tvOS Direct Play startup gate no longer treats sparse `loadedTimeRanges` as unsafe for progressive streams; high-bitrate Direct Play now starts from AVPlayer `readyToPlay` instead of waiting 45s and rebuilding as transcode.
- Direct Play remains the preferred route once selected, but it is no longer mandatory after an observed post-start stall on high-bitrate/premium tvOS progressive playback.
- The earlier slow-start log (`resume=4655s`, `ready min=0 preferred=0`, then `readiness.timeout elapsed=17s`) was addressed by allowing zero-buffer Direct Play gates on lower-risk progressive assets; M22 keeps high-bitrate/premium tvOS Direct Play on a measured-buffer no-stall path.
- tvOS progressive Direct Play warmup no longer performs disposable URLSession range probes, removing a competing request that was timing out against the same Jellyfin stream while AVPlayer was trying to start.
- tvOS Direct Play no longer forces a 90s startup buffer for premium progressive files; that target made the first-frame path visibly slower and encouraged large progressive reads before playback could prove the connection was healthy.
- tvOS cache ramp decisions now use elapsed playback time since the first frame, not the resumed movie position, so resuming at `4655s` cannot immediately jump to hot/deep/flood buffering.
- Resume-based HLS/transcode no longer applies an absolute deferred seek after first frame, avoiding the post-start timebase churn seen when fallback streams began at `StartTimeTicks`.
- Progressive Direct Play warmup now skips disposable URLSession range probes on iOS as well as tvOS, so the only startup reader for remote MP4/MOV is AVPlayer itself.
- iOS high-bitrate progressive Direct Play now gates on `readyToPlay` for preroll instead of requiring measured 5-10s buffer telemetry before playback intent, reducing avoidable first-frame delay while keeping the audio/video sync guard.
- Home featured playback now presents the native full-screen player before session resolution completes, matching Detail startup behavior and making the user action feel immediate.
- The latest tvOS cut-after-start log (`DirectPlay`, `bitrate=21868794`, first frame after ~6.3s, then `MEDIA_PLAYBACK_STALL`) supersedes the earlier "Direct Play mandatory" tuning: high-bitrate/premium tvOS progressive Direct Play now uses a 24s no-stall forward-buffer target with `automaticallyWaitsToMinimizeStalling`, no longer qualifies for immediate zero-buffer readiness, and a stall within 20s of first frame recovers through direct-route-disabled HLS/transcode fallback.
- Playback item observers now guard the current `AVPlayerItem` before mutating playback state, and delayed startup subtitle selection/video validation tasks are canceled on stop, reload, replacement, and first-frame completion.
- The follow-up tvOS stall log (`bitrate=21868794`, `MEDIA_PLAYBACK_STALL` after a slow progressive start, fallback racing while old DirectPlay still emitted proof/stall telemetry) initially exposed a bad overcorrection: preemptive HLS/transcode added multi-second resolution cost and could abandon the native route. Auto-quality tvOS Direct Play now stays Direct Play when the configured streaming budget has clear headroom over the source bitrate.
- Compatible high-bitrate tvOS Direct Play skips the startup readiness delay and keeps the fast Direct Play buffer policy when network headroom is known. Apple still gets the native progressive file path first; fallback is reserved for explicit over-budget cases or real playback failure evidence.
- Startup-readiness, preroll, and preflight failures no longer replay the same progressive Direct Play route; profile recovery suspends the old player item, cancels observers/prerolls/validation/proof tasks, and then loads the fallback route with the current resume position.
- Fallback/profile re-resolution now preserves `StartTimeTicks`, and pinned HLS variant URLs carry resume query parameters from the master playlist URL so a Resume action cannot silently rebuild a zero-second playlist.
- Home and Library duplicate enrichment now score local playback quality from existing metadata instead of resolving playback sources or warming media routes during feed/list normalization, removing the repeated `playback.selection` network storm seen before the user clicked Play.
- Periodic playback progress still saves local position on every player tick, but remote Jellyfin `/Sessions/Playing/Progress` updates are throttled, latest-wins, and paused during route recovery so telemetry cannot compete with media startup/fallback traffic.
- The latest The Boys black-screen log (`audio_only_no_video` after Direct Play DV/HDR10+ advanced playback without a decoded frame) is now treated as a structured video-decode failure. It no longer reloads the same Direct Play URL; recovery suspends the old item and disables direct routes so the next candidate must be a profile fallback. `directplay_stall` remains the only same-route Direct Play recovery reason.

## Validation Results

- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests`: passed, 123 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/HomeViewModelFeedEnrichmentTests/testLoadPrefersLocalPlaybackQualityWithoutWarmupWhenDuplicateCandidatesShareTheSameMovie -only-testing:PlaybackEngineTests/LibraryViewModelTests/testLoadInitialPrefersLocalPlaybackQualityWithoutResolvingSourcesAcrossLibraries`: passed, 2 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackStopReportingTests`: passed, 125 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests`: passed, 140 tests
- `xcodegen generate`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `git diff --check`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinBlackScreenDD -only-testing:PlaybackEngineTests/PlaybackPolicyTests/testStartupRecoveryDisablesDirectRoutesForUnsafeProgressiveFailures -only-testing:PlaybackEngineTests/PlaybackPolicyTests/testStartupFailureReasonAudioOnlyNoVideoTriggersRecovery -only-testing:PlaybackEngineTests/PlaybackPolicyTests/testStartupFailureReasonRawValueRoundTrip -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests/testStartupDirectPlayFailuresSkipSameRouteRecovery -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests/testVideoDecodeFailuresDisableDirectRouteRecovery`: passed, 5 tests
- `xcodegen generate`: passed
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests -only-testing:PlaybackEngineTests/PlaybackWarmupManagerTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackResumeSeekPlannerTests -only-testing:PlaybackEngineTests/PlaybackTVOSCachingPolicyTests`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed after rerunning sequentially
- `git diff --check`: passed
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed
- `xcodegen generate`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests -only-testing:PlaybackEngineTests/PlaybackWarmupManagerTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed, 82 tests
- `git diff --check`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodebuild build -quiet -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild test -quiet -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackPolicyTests -only-testing:PlaybackEngineTests/PlaybackResumeSeekPlannerTests -only-testing:PlaybackEngineTests/PlaybackTVOSCachingPolicyTests`: passed
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
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStopReportingTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:ReelFinTVUITests/TVLiveNavigationSmokeUITests`: passed with 3 expected skips because the simulator had no persisted authenticated tvOS session
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests/testPrepareEpisodePlaybackLatestWinsAcrossWarmupSignals`: passed, 14 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:ReelFinUITests/AppStoreScreenshotTests`: passed, 4 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/MediaGatewayCacheKeyTests -only-testing:PlaybackEngineTests/MediaGatewayIndexTests -only-testing:PlaybackEngineTests/HLSSegmentDiskCacheTests`: passed, 13 tests
- `bash -n scripts/run_zero_stall_validation.sh`: passed
- `scripts/run_zero_stall_validation.sh`: passed, artifacts in `.artifacts/zero-stall/20260419-160313`
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed, 57 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: not runnable because `PlaybackEngineTests` is not a member of the `ReelFinTV` scheme/test plan
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed, 2 tests
- `xcodegen generate`: passed for build `1.0 (5)`
- `xcodebuild archive -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'generic/platform=tvOS' -archivePath .artifacts/testflight/ReelFin-tvOS-b5.xcarchive DEVELOPMENT_TEAM=WZ4CHJH7TA CODE_SIGN_STYLE=Automatic`: passed
- `xcodebuild -exportArchive -archivePath .artifacts/testflight/ReelFin-tvOS-b5.xcarchive -exportPath .artifacts/testflight/export-b5 -exportOptionsPlist .artifacts/testflight/ExportOptions-tvOS-manual.plist`: passed
- `codesign -dv --verbose=2 /tmp/reelfin-ipa-b5/Payload/ReelFin.app` plus `Info.plist` checks: passed, `com.reelfin.app`, version `1.0`, build `5`
- `asc publish testflight --app 6762079357 --ipa .artifacts/testflight/export-b5/ReelFin.ipa --platform TV_OS --version 1.0 --build-number 5 --group "Internal Testers" --wait`: passed, build `0974cb76-e710-4f90-922f-0d5731d765c7`, processing state `VALID`
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinZeroStallDerivedData -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed, 42 tests
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinZeroStallDerivedData -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests -only-testing:PlaybackEngineTests/PlaybackPolicyTests`: passed, 124 tests
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath /tmp/ReelFinDetailWarmupDerivedData -only-testing:PlaybackEngineTests/PlaybackWarmupManagerTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests`: passed, 8 tests
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

## Remaining High-Value Follow-Ups

- Split scroll-linked and hydration state out of `HomeView` and `DetailView` so focus and phased-loading updates do not invalidate large view roots.
- Continue the playback lifecycle hardening pass for observer callbacks and reload paths that still hop through ad hoc `Task` boundaries.
- Add launch/signpost regression assertions and stronger playback TTFF checks so performance assumptions stop living only in manual scripts.
- Wire the persistent media cache foundations into the playback routes: HLS segment serving first, then direct-play prefetch/spooling once Range behavior and AVPlayer source promotion are proven stable.

## Rejected Or Deferred Optimizations

- Replacing Apple playback with VLC or FFmpeg: dangerous and outside current product constraints.
- Rewriting SwiftUI rails into `UICollectionView`: not justified without fresh measurement after first-wave fixes.
- Replacing GRDB or rewriting DTO decoding: no current evidence that they are the top bottleneck.
- Large Xcode target-graph surgery: needs measurement first.
