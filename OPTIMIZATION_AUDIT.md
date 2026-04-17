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
   Fix: keep pushing delayed validation, seek invalidation, and hot observer work into cancelable or session-scoped ownership.

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

## Validation Results

- `xcodegen generate`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/RootViewModelAuthPersistenceTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/HomeViewModelActionTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/LibraryViewModelTests`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -only-testing:PlaybackEngineTests/PlaybackStopReportingTests -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'`: passed
- `xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'`: passed
- `xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:ReelFinTVUITests/TVLiveNavigationSmokeUITests`: passed with 3 expected skips because the simulator had no persisted authenticated tvOS session

## Remaining High-Value Follow-Ups

- Split scroll-linked and hydration state out of `HomeView` and `DetailView` so focus and phased-loading updates do not invalidate large view roots.
- Continue the playback lifecycle hardening pass for observer callbacks and reload paths that still hop through ad hoc `Task` boundaries.
- Add launch/signpost regression assertions and stronger playback TTFF checks so performance assumptions stop living only in manual scripts.

## Rejected Or Deferred Optimizations

- Replacing Apple playback with VLC or FFmpeg: dangerous and outside current product constraints.
- Rewriting SwiftUI rails into `UICollectionView`: not justified without fresh measurement after first-wave fixes.
- Replacing GRDB or rewriting DTO decoding: no current evidence that they are the top bottleneck.
- Large Xcode target-graph surgery: needs measurement first.
