# ReelFin Cinematic Editorial UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved Cinematic Editorial Glass+ redesign across ReelFin Home, Library/Search, and Detail on iOS and tvOS while improving artwork scheduling, preserving navigation/focus/playback behavior, and proving fluidity in the configured simulators.

**Architecture:** Add small pure policies for editorial visuals, motion, artwork roles, and Detail rendering cost; keep the existing screen roots and navigation topology; move Library intent ownership into its view model; route speculative artwork through the authenticated image pipeline with bounded concurrency; and use native SwiftUI Liquid Glass only for interactive chrome and the currently focused tvOS surface.

**Tech Stack:** Swift 5.9, SwiftUI on iOS/tvOS 26, Observation, async/await, ImageIO, XCTest, XcodeGen, xcodebuild, iOS/tvOS Simulator.

## Global constraints

- Preserve the current dirty worktree and edit `project.yml` only if target membership actually changes. New Swift files under existing source/test folders are picked up by XcodeGen.
- Preserve native `TabView`, `NavigationStack`, iOS zoom transitions, tvOS inline Detail, native `Button` activation, exact focus provenance, and Apple-native playback.
- Preserve cache-first Home/Library painting and authenticated image headers.
- No full-screen live glass, per-resting-card glass, animated large blur radius, full-screen drawing-group animation, fixed-sleep focus handoff, or third-party rendering framework.
- Every behavior change starts with a focused failing test. Run the exact RED command, make the smallest GREEN change, rerun, then refactor.
- After each task, run `git diff --check` and inspect only the task's diff before proceeding.

---

## Task 1: Establish the editorial visual, motion, and accessibility policies

**Files:**

- Create: `ReelFinUI/Sources/ReelFinUI/Theme/EditorialBrowseVisualSystem.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Theme/ReelFinTheme.swift`
- Create: `Tests/PlaybackEngineTests/EditorialBrowseVisualSystemTests.swift`

- [x] **Step 1: Write failing policy tests**

Add tests for automatic hero eligibility, deterministic next index, motion durations, Reduce Motion, Reduce Transparency, glass roles, and Detail artwork cost:

```swift
@testable import ReelFinUI
import XCTest

final class EditorialBrowseVisualSystemTests: XCTestCase {
    func testHeroRotationRequiresActiveUnassistedIdleMotion() {
        XCTAssertTrue(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: true,
            isUserInteracting: false,
            reduceMotion: false,
            voiceOverEnabled: false,
            itemCount: 2
        ))
        XCTAssertFalse(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: false,
            isUserInteracting: false,
            reduceMotion: false,
            voiceOverEnabled: false,
            itemCount: 2
        ))
        XCTAssertFalse(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: true,
            isUserInteracting: true,
            reduceMotion: false,
            voiceOverEnabled: false,
            itemCount: 2
        ))
        XCTAssertFalse(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: true,
            isUserInteracting: false,
            reduceMotion: true,
            voiceOverEnabled: false,
            itemCount: 2
        ))
        XCTAssertFalse(HeroRotationPolicy.allowsAutomaticAdvance(
            sceneIsActive: true,
            isUserInteracting: false,
            reduceMotion: false,
            voiceOverEnabled: true,
            itemCount: 2
        ))
    }

    func testEditorialMotionAndGlassFallbacksAreAccessible() {
        XCTAssertEqual(EditorialMotion.heroPageDuration(reduceMotion: false), 0.21)
        XCTAssertEqual(EditorialMotion.heroPageDuration(reduceMotion: true), 0.18)
        XCTAssertEqual(EditorialMotion.focusScale(role: .libraryPoster, reduceMotion: true), 1.02)
        XCTAssertEqual(EditorialGlassRole.focusedMedia.presentation(reduceTransparency: true), .opaque)
        XCTAssertEqual(EditorialGlassRole.actionCluster.presentation(reduceTransparency: false), .interactiveGlass)
    }

    func testDetailArtworkPolicyUsesOneHeroAndCheapNeighbors() {
        XCTAssertEqual(DetailArtworkCostPolicy.role(isSelected: true), .hero)
        XCTAssertEqual(DetailArtworkCostPolicy.role(isSelected: false), .preview)
        XCTAssertEqual(DetailArtworkCostPolicy.heroLayerBudget(isSelected: true), 1)
        XCTAssertEqual(DetailArtworkCostPolicy.heroLayerBudget(isSelected: false), 0)
    }
}
```

- [x] **Step 2: Run the focused test and confirm RED**

```bash
xcodegen generate
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:PlaybackEngineTests/EditorialBrowseVisualSystemTests
```

Expected: compile failure because the policies do not exist.

- [x] **Step 3: Implement the pure system**

In `EditorialBrowseVisualSystem.swift`, add internal testable types with these stable interfaces:

```swift
enum EditorialGlassPresentation: Equatable { case interactiveGlass, passiveGlass, opaque }
enum EditorialGlassRole { case navigation, actionCluster, compactControl, focusedMedia }
enum DetailArtworkRole: Equatable { case hero, preview }

enum HeroRotationPolicy {
    static func allowsAutomaticAdvance(
        sceneIsActive: Bool,
        isUserInteracting: Bool,
        reduceMotion: Bool,
        voiceOverEnabled: Bool,
        itemCount: Int
    ) -> Bool
    static func nextIndex(currentIndex: Int, itemCount: Int) -> Int?
}

enum EditorialMotion {
    static func heroPageDuration(reduceMotion: Bool) -> TimeInterval
    static func focusScale(role: TVMotion.FocusRole, reduceMotion: Bool) -> CGFloat
    static func buttonPressAnimation(reduceMotion: Bool) -> Animation
}

enum DetailArtworkCostPolicy {
    static func role(isSelected: Bool) -> DetailArtworkRole
    static func heroLayerBudget(isSelected: Bool) -> Int
}
```

Extend `ReelFinTheme` with `editorialAccent`, primary/secondary text, glass tint, focused rim, and opaque fallback. Keep global `accent` white.

- [x] **Step 4: Make the focused suite GREEN**

Run the command from Step 2. Expected: all new tests pass.

- [x] **Step 5: Refactor and validate diff**

Centralize only repeated literals; do not create a generic design-system abstraction beyond the approved roles.

---

## Task 2: Canonicalize artwork roles and route prefetch through the authenticated pipeline

**Files:**

- Create: `Shared/Sources/Shared/ArtworkRequest.swift`
- Modify: `Shared/Sources/Shared/Protocols.swift`
- Create: `ImageCache/Sources/ImageCache/DefaultArtworkPrefetcher.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Components/CachedRemoteImage.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Components/PosterCardView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/ReelFinDependencies.swift`
- Modify: `ReelFinApp/App/AppContainer.swift`
- Modify: `ReelFinApp/AppTV/TVAppBootstrap.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/PreviewMocks.swift`
- Modify: `SyncEngine/Sources/SyncEngine/DefaultSyncEngine.swift`
- Modify: `JellyfinAPI/Sources/JellyfinAPI/JellyfinAPIClient.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Detail/DetailViewModel.swift`
- Create: `Tests/PlaybackEngineTests/ArtworkRequestTests.swift`
- Create: `Tests/ImageCacheTests/DefaultArtworkPrefetcherTests.swift`
- Modify: `Tests/PlaybackEngineTests/DefaultSyncEngineHomeFeedTests.swift`
- Modify: ReelFinDependencies construction in `Tests/PlaybackEngineTests/*`

- [x] **Step 1: Write failing canonical request tests**

Add public Sendable value roles in Shared and test exact identity/type/profile mapping. Poster grid/row use Primary; landscape and hero use Backdrop when `backdropTag` exists and Primary otherwise; episode artwork uses `parentID ?? id`; logo stays on the displayed item. The same value must be usable by a visible `CachedRemoteImage` and speculative prefetch.

```swift
func testEveryArtworkRoleUsesItsCanonicalProfile() {
    for role in ArtworkRequestRole.allCases {
        XCTAssertEqual(
            ArtworkRequest.make(for: item, role: role).profile,
            role.profile
        )
    }
}

func testEpisodeLandscapeRequestUsesSeriesIdentity() {
    let request = ArtworkRequest.make(for: episode, role: .landscapeRail)
    XCTAssertEqual(request.itemID, episode.parentID)
}
```

- [x] **Step 2: Confirm RED**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:PlaybackEngineTests/ArtworkRequestTests
```

- [x] **Step 3: Implement the canonical request value and bridge**

Create these exact public interfaces in Shared:

```swift
public struct ArtworkRequest: Hashable, Sendable {
    public let itemID: String
    public let type: JellyfinImageType
    public let profile: ArtworkRequestProfile

    public static func make(for item: MediaItem, role: ArtworkRequestRole) -> ArtworkRequest
}

public enum ArtworkRequestRole: CaseIterable, Sendable {
    case posterGrid, posterRow, landscapeRail, heroLow, heroHigh, logo, avatar

    public var profile: ArtworkRequestProfile { get }
}

public protocol ArtworkURLProviding: AnyObject, Sendable {
    func imageURL(for request: ArtworkRequest) async -> URL?
}

public protocol ArtworkPrefetching: AnyObject, Sendable {
    func prefetch(_ requests: [ArtworkRequest]) async
}
```

Make `JellyfinAPIClientProtocol` inherit `ArtworkURLProviding`; provide the bridge implementation in its extension by forwarding the request's profile width/quality to the existing URL method. Existing API mocks must not need a second URL implementation.

Add `CachedRemoteImage.init(request:...)` and keep the old initializer temporarily for unchanged call sites. Change `PosterCardArtworkView` to use `.posterRow`, `.posterGrid`, or `.landscapeRail` through `ArtworkRequest.make`; delete its raw 360/400 image literals.

- [x] **Step 4: Write RED tests for the authenticated prefetch adapter**

`DefaultArtworkPrefetcherTests` must prove that requests are resolved through `ArtworkURLProviding`, URLs are de-duplicated in first-seen order, cancellation stops URL resolution and prevents pipeline start, and one batch reaches `ImagePipelineProtocol.prefetch(urls:)`. Extend the existing image-pipeline authentication coverage so prefetch ultimately produces `X-Emby-Token`, not an API-session fetch-and-discard.

- [x] **Step 5: Implement and wire one prefetch path**

Implement `DefaultArtworkPrefetcher` as an actor in ImageCache. It resolves requests sequentially with cancellation checks, de-duplicates resolved URLs while preserving order, then invokes the image pipeline once.

Add a required `artworkPrefetcher: any ArtworkPrefetching` dependency to `ReelFinDependencies`. Construct one shared production instance from the API client and image pipeline in iOS/tvOS containers, inject it into SyncEngine and ReelFinDependencies, and provide explicit test/preview doubles at every initializer call site. Do not add an optional/no-op production fallback.

Change `DefaultSyncEngine` to accept `ArtworkPrefetching` instead of `ImagePipelineProtocol`. Build canonical request values: Continue Watching and Next Up use `.landscapeRail`; catalog rows use `.posterRow`; featured items use `.heroLow`. Store one cancelable `prefetchTask`, cancel it before replacing it, and use structured `Task(priority:)`, not `Task.detached`.

Replace the four ReelFinUI `apiClient.prefetchImages` call sites with canonical requests sent to `dependencies.artworkPrefetcher`. Home/Library Detail-entry warmup uses `.heroHigh`; related/similar items use `.posterRow`; Library focus may batch `.posterGrid` plus `.heroHigh`. Keep each call inside its existing owned/cancelable warmup scope.

Delete `prefetchImages(for:)` from `JellyfinAPIClientProtocol`, its default extension, and `JellyfinAPIClient`. Extra same-named methods in unrelated test doubles may remain but no production call site may use them.

- [x] **Step 6: Make canonical/prefetch/Sync tests GREEN**

Add Sync tests that inspect captured `ArtworkRequest` values and prove row-role mapping and latest prefetch-task replacement. Run:

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:PlaybackEngineTests/ArtworkRequestTests \
  -only-testing:PlaybackEngineTests/DefaultSyncEngineHomeFeedTests \
  -only-testing:ImageCacheTests/DefaultArtworkPrefetcherTests \
  -only-testing:ImageCacheTests/DefaultImagePipelineTests
rg -n 'prefetchImages\(' ReelFinUI SyncEngine JellyfinAPI Shared
```

Expected: tests pass and `rg` has no production matches.

- [x] **Step 7: Regenerate and build both app targets**

Run XcodeGen, then build iOS and tvOS sequentially (or with distinct DerivedData paths). Both targets must compile because Shared/ImageCache/ReelFinDependencies changes are cross-platform.

---

## Task 3: Bound image prefetch/decode work and prevent stale publication

**Files:**

- Modify: `ImageCache/Sources/ImageCache/DefaultImagePipeline.swift`
- Create: `ImageCache/Sources/ImageCache/ImageDecodeScheduler.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Components/CachedRemoteImage.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Components/CachedRemoteImageSupport.swift`
- Create: `ReelFinUI/Sources/ReelFinUI/Components/CachedRemoteImageLoader.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Components/ShimmerView.swift`
- Create: `Tests/ImageCacheTests/ImagePrefetchConcurrencyTests.swift`
- Create: `Tests/ImageCacheTests/ImageDecodeSchedulerTests.swift`
- Create: `Tests/PlaybackEngineTests/CachedRemoteImageLoaderTests.swift`
- Create: `Tests/PlaybackEngineTests/ShimmerAnimationPolicyTests.swift`

- [x] **Step 1: Add failing request-generation and loader race tests**

Test `CachedRemoteImageRequestState` and a `@MainActor` loader without hosting SwiftUI. Use controlled continuations to suspend each await. Prove an old URL resolution cannot attach after a newer generation starts; old cached/primary/fallback results cannot publish; invalidation cancels the attached URL; cancellation prevents publication; and an old generation finishing cannot clear a newer URL.

```swift
func testOldCachedLookupCannotPublishAfterNewGenerationStarts() async {
    let first = Task { await loader.load(descriptor: descriptorA, ...) }
    await pipeline.waitUntilCacheLookupIsSuspended(for: urlA)
    await loader.load(descriptor: descriptorB, ...)
    await pipeline.resumeCacheLookup(for: urlA, with: imageA)
    await first.value
    XCTAssertTrue(loader.image === imageB)
    XCTAssertEqual(firstCallbackCount, 0)
}
```

- [x] **Step 2: Implement generation ownership and guard every suspension**

Add `CachedRemoteImageRequestToken`, cancellation value, and request state with `begin`, `owns`, `attach`, `finish`, and `invalidate`. `begin` advances a wrapping generation and returns cancellation for the previous token. `finish` and `invalidate` never clear newer state.

Move asynchronous load work into `CachedRemoteImageLoader`. Preserve both Task 2 `CachedRemoteImage` initializers. Check cancellation and token ownership immediately after: main URL resolution, cache lookup, main download, fallback URL resolution, and fallback download; also guard before logging or starting fallback. Publication and callback go through one guarded method. `onDisappear` invalidates first, then cancels the captured URL/consumer. A defer uses only token-local URL/consumer values.

- [x] **Step 3: Confirm the loader suite GREEN**

Run `PlaybackEngineTests/CachedRemoteImageLoaderTests`; all continuation-driven races must complete without sleeps.

- [x] **Step 4: Add RED tests for a fixed four-request prefetch window**

Use a blocking URLProtocol with explicit start/completion signals and distinct hosts. Test: exactly four start before completion; completing one admits exactly one; cancelling the parent never admits waiting URLs; duplicate URLs consume one slot; candidates remain capped at 24.

- [x] **Step 5: Implement stable bounded prefetch**

Use internal constants `maximumConcurrentPrefetches = 4` and `maximumPrefetchURLs = 24`. Stable-deduplicate first, keep unadmitted URLs only in an iterator, seed at most four group children, and add one URL per completion. On cancellation call `group.cancelAll()` and return without admitting another URL. Preserve registry deduplication, token headers, cache keys, memory accounting, and visible/focused work behavior.

- [x] **Step 6: Add RED tests for a fixed two-operation decode scheduler**

Test maximum two active bodies, one-for-one admission, cancellation before start, cancellation while running, cancellation before operation installation, invalid payload, and permit release. Tests may block only dedicated OperationQueue threads, never Swift cooperative-executor threads.

- [x] **Step 7: Implement `ImageDecodeScheduler` with OperationQueue**

Use `OperationQueue` named `com.reelfin.image-decode`, quality `.utility`, and `maxConcurrentOperationCount = 2`. A synchronous `DecodeOperation` owns the ImageIO body. Resume its continuation only from `completionBlock`; cancellation only cancels the installed/soon-to-be-installed operation through a locked handle. Reject a cancelled result after continuation. Keep the current ImageIO thumbnail options and requested pixel sizing. `cachedImage(for:)` remains nonthrowing and returns nil on decode cancellation; disk/network task paths propagate cancellation.

- [x] **Step 8: Add RED shimmer policy tests, then split static/animated branches**

Add `ShimmerAnimationPolicy.branch(animationEnabled:reduceMotion:)`. Public `ShimmerView.init(animationEnabled: Bool = true)` remains source-compatible. `AnimatedShimmerView` alone owns phase/repeatForever; `StaticShimmerView` owns none. Select distinct branch types/IDs so changing Reduce Motion destroys the running animation. tvOS stays static.

- [x] **Step 9: Run the complete affected gates and both builds**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:ImageCacheTests \
  -only-testing:PlaybackEngineTests/CachedRemoteImageLoaderTests \
  -only-testing:PlaybackEngineTests/ShimmerAnimationPolicyTests
```

Regenerate with XcodeGen, build iOS and tvOS sequentially or with distinct DerivedData, run `git diff --check`, and verify Task 2's authenticated/canonical artwork tests remain green.

---

## Task 4: Recompose Home with logo-first identity, accessible carousel motion, and Glass+ actions

**Files:**

- Modify: `ReelFinUI/Sources/ReelFinUI/Theme/EditorialBrowseVisualSystem.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Components/HeroCarouselView.swift`
- Create: `ReelFinUI/Sources/ReelFinUI/Components/EditorialMediaIdentityView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Components/CinematicBackdropView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Theme/ReelFinTheme.swift`
- Modify: `Tests/PlaybackEngineTests/EditorialBrowseVisualSystemTests.swift`
- Modify: `Tests/PlaybackEngineTests/TVPerformanceStateTests.swift`
- Modify: `Tests/PlaybackEngineTests/TVUXPolishLayoutTests.swift`
- Modify: `Tests/ReelFinUITests/HomeAndDetailActionsUITests.swift`
- Modify: `PLANS.md`
- Modify: `OPTIMIZATION_AUDIT.md`

- [x] **Step 1: Extend failing Home policy/layout tests**

Add small pure seams before touching the views:

```swift
enum HeroPageChangeOrigin { case automatic, direct }

extension HeroRotationPolicy {
    static func allowsHaptic(for origin: HeroPageChangeOrigin) -> Bool
}

enum CinematicBackdropLayerPolicy {
    enum Source: Equatable { case item, fallback, none }
    static let artworkLayerCount = 2
    static func source(hasItem: Bool, hasFallbackItem: Bool) -> Source
}

enum HomeEditorialPresentationPolicy {
    static let activeIndicatorWidth: CGFloat = 24
    static let inactiveIndicatorWidth: CGFloat = 8
    static let focusedShadowRadius: CGFloat = 34
    static let focusedShadowYOffset: CGFloat = 18
    static func focusedMediaGlass(
        isFocused: Bool,
        reduceTransparency: Bool
    ) -> EditorialGlassPresentation?
}
```

Test that automatic page changes never request haptics while direct changes may; an item replaces the fallback backdrop, fallback is used only without an item, and the artwork budget is exactly two layers; resting media has no glass, focused media is passive glass, Reduce Transparency produces opaque focused media, and the focused shadow stays fixed at `34/18`. Keep the already-green `nextIndex`, single-item, duration, and glass role assertions as regression coverage rather than pretending they are RED.

- [x] **Step 2: Confirm targeted RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:PlaybackEngineTests/EditorialBrowseVisualSystemTests \
  -only-testing:PlaybackEngineTests/TVPerformanceStateTests \
  -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests
```

- [x] **Step 3: Make hero rotation owned and accessible**

In the iOS hero, observe scene phase, Reduce Motion, Reduce Transparency, and VoiceOver. Track touch/drag interaction with a simultaneous zero-distance gesture so the native `TabView` paging gesture remains intact. Gate timer advancement through `HeroRotationPolicy`, calculate the next page with `nextIndex`, and use only a local `.easeInOut(duration: EditorialMotion.heroPageDuration(...))` animation. Remove `.sensoryFeedback(trigger: currentIndex)` from Play: an automatic timer tick must never generate haptics. Preserve the public initializer, the selected-item binding/callbacks, transition IDs, and all existing favorite identifiers.

- [x] **Step 4: Add shared logo-first identity**

Create `EditorialMediaIdentityView` with `iosHero`, `tvHero`, and `landscapeRail` styles plus item, fallback title, optional kicker/metadata, API client, and image pipeline. Resolve the canonical `.logo` `ArtworkRequest`, use the authenticated `apiClient.imageURL(for:)` path, check the shared cache before transport, and pass both cached and downloaded images through the existing `TransparentImageCropper.readableLogoImage`. Check task cancellation after every suspension and immediately before publishing. The text fallback must render immediately, actions must never wait for a logo, the image is decorative, and the combined element exposes the media name as a header. Fade logo opacity using `EditorialMotion`; do not animate layout size. Extract/reuse the existing cropper—do not duplicate its pixel logic. Replace `TVHeroTitleView`, the iOS hero text title, and `ImmersiveRowArtworkTitleView` with this component; leave Detail identity for Task 7.

- [x] **Step 5: Apply editorial Home composition**

On iOS, compose kicker → logo/title → one metadata line → actions, then use champagne only for the active capsule indicator. Keep the media backdrop itself tappable and add a distinct More circle calling `onTap(item)` with identifier `home_featured_more_button_<id>`. Put Play, Favorite, and More in one stable `GlassEffectContainer(spacing: 12)`, applying one interactive effect per control—never to the container/HStack—and provide an opaque tonal fallback when Reduce Transparency is enabled. Use a private press style driven by `EditorialMotion` and suppress scale under Reduce Motion. Apply compact-control glass only to each section chevron, not the header row. Add a UI regression proving More opens Detail.

On tvOS, preserve native `Button`, `TVNoChromeButtonStyle`, focus IDs, `.onMoveCommand`, action order, and the existing single-action topology. Give the action the `actionCluster` presentation with an opaque Reduce Transparency fallback. Keep promo/quality badges static tonal (they are not controls). Only a focused Home shelf card receives passive media glass; resting cards have no glass/rim, and Reduce Transparency uses opaque tonal focus. Keep the fixed `34/18` focused shadow, current matched transitions/focus modifiers, and focus scale; route the latter through `EditorialMotion.focusScale` in `TVMotionFocusModifier`.

- [x] **Step 6: Reduce backdrop variants**

Resolve exactly one displayed source: current item, otherwise fallback, otherwise none. Render exactly one low-resolution blurred `.heroLow` request plus one sharp `.heroHigh` request for that source. Remove the second blur, full-screen material wash, and `.drawingGroup()`; retain the cheap gradient scrims. Fire `onHeroImageVisible` only from the sharp layer. Keep the Home call site and its ambient telemetry semantics unchanged.

- [x] **Step 7: Keep the change scoped and document the hot path**

Do not change navigation roots, playback routing, Home section ordering, transition identities, public hero API, or tvOS focus topology. Record the two-layer backdrop, cache-first logo identity, owned carousel motion, and Glass placement in `PLANS.md` and `OPTIMIZATION_AUDIT.md`.

- [x] **Step 8: Validate Home tests, UI route, and both builds**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:PlaybackEngineTests/EditorialBrowseVisualSystemTests \
  -only-testing:PlaybackEngineTests/TVPerformanceStateTests \
  -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:ReelFinUITests/HomeAndDetailActionsUITests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.5'
```

Run `xcodegen generate` before the builds, execute the two platform builds sequentially (or with distinct DerivedData paths), and finish with `git diff --check`.

---

## Task 5: Make Library intents genuinely latest-wins

**Files:**

- Modify: `ReelFinUI/Sources/ReelFinUI/Library/LibraryViewModel.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift`
- Modify: `Tests/PlaybackEngineTests/LibraryViewModelTests.swift`

- [ ] **Step 1: Add deterministic failing overlap tests**

Convert the API and repository doubles to actor-backed, continuation-controlled gates that can deliberately ignore cancellation. Record complete query snapshots and expose count waiters/resume methods so the tests never sleep. Add these exact overlap cases:

1. `testLatestCriteriaWinsWhenOlderRemoteFetchFinishesLast`: block remote A, submit and finish B, then finish A; only coherent B criteria/results may publish.
2. `testFilterAndSortReloadStartsWhilePreviousPaginationIsSuspended`: block A page 1, submit new filter/sort B, prove B page 0 starts immediately, then finish stale A without append or page-state damage.
3. `testCancelIntentPreservesLastCommittedCachedSearchResults`: publish owned cached search results, cancel while remote is blocked, then release stale work; committed cache stays visible.
4. `testIsLoadingPageTracksOnlyCurrentCriteriaGeneration`: an old pagination completion must not clear the loading owner of current B.

Drive the model through a synchronous, model-owned submission API that returns its owned `Task` so tests can await exact completion. Preserve immediate test-double behavior when no gate is configured and keep the existing aggregation/playback-quality tests.

- [ ] **Step 2: Confirm RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:PlaybackEngineTests/LibraryViewModelTests
```

- [ ] **Step 3: Implement owned generation/task semantics**

Add immutable `LibraryCriteria: Equatable, Sendable` containing the trimmed search query, filter, and sort mode. Make `SortMode` sendable. Add separate owned state for criteria and pagination: a criteria generation, pagination request ID, active criteria, `criteriaTask`, `paginationTask`, and a loading owner token. A synchronous criteria submission must:

1. capture all mutable UI criteria before suspension;
2. increment the generation;
3. cancel and replace both owned tasks and invalidate pagination/loading ownership;
4. reset page/end markers without clearing the last committed items;
5. start and return the new owned task.

Pagination captures generation, criteria, request ID, and page synchronously; it is rejected only for current-generation criteria loading, nonempty search, last page, or an existing current pagination task. A new criteria intent must still start while old pagination is suspended.

Pass captured criteria/tokens through cache, query, view-resolution, remote, merge, sort, and persistence helpers. After **every** repository/API suspension—including cached views, remote views, saving views, item fetches, searches, and upserts—require both `!Task.isCancelled` and matching ownership before publishing or starting another dependency call. Cancellation alone is insufficient because transports and test continuations may ignore it. Build and sort only from captured criteria, never mutable properties after an `await`. Clear loading state only when the completing task still owns its token; log only errors that still belong to the active intent.

Preserve cached-first painting and all existing semantics: local search then remote merge for nonempty search; cached library query then remote replacement for empty search; 120/48 page sizes, view-ID scoping, pagination numbering, deduplication, playback-quality preference, and disabled pagination during search. Keep `LibraryViewModel` on `MainActor`; do not add detached tasks or broaden actor isolation.

- [ ] **Step 4: Remove unowned view Tasks**

Add a dedicated `@State` search-debounce task; do not reuse artwork/playback `warmupTask`. Initial load submits one owned criteria intent. Search changes cancel the prior debounce, sleep 250 ms in `do/catch`, then submit the latest full criteria synchronously. Filter or sort changes cancel any pending debounce and submit immediately so delayed search cannot undo the newer choice. Pagination visibility submits through the model-owned pagination API instead of creating an anonymous view task. On disappearance, cancel/nil the debounce and call the model cancellation API while preserving existing warmup/focus cancellation. Returning to Library resubmits current criteria while already committed items can paint immediately.

- [ ] **Step 5: Make Library tests GREEN and verify both platform branches**

Run Step 2, then regenerate and build iOS/tvOS sequentially:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.5'
git diff --check
```

Record the latest-wins ownership/cancellation work in `PLANS.md` and `OPTIMIZATION_AUDIT.md`.

---

## Task 6: Apply the editorial expanded/compact Library composition and immediate tvOS activation

**Files:**

- Modify: `ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Library/TVLibraryPosterCard.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Components/StickyBlurHeader.swift`
- Create: `Tests/PlaybackEngineTests/LibraryEditorialLayoutTests.swift`
- Modify: `Tests/PlaybackEngineTests/TVUXPolishNavigationTests.swift`

- [ ] **Step 1: Add failing pure layout/activation tests**

Add a `LibraryHeaderPresentation` pure policy whose compact state changes only after a quantized threshold, and a `TVLibraryActivationPolicy` that reports zero selection delay. Preserve existing top-row routing and focus source IDs in navigation tests.

- [ ] **Step 2: Confirm RED**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:PlaybackEngineTests/LibraryEditorialLayoutTests \
  -only-testing:PlaybackEngineTests/TVUXPolishNavigationTests
```

- [ ] **Step 3: Stop per-pixel header invalidation where unnecessary**

In `StickyBlurHeader`, do not install scroll tracking for `.always`. For reveal/collapse behavior, map raw offset to a small quantized presentation value before state assignment and skip identical values.

- [ ] **Step 4: Build expanded plus compact iOS header**

Move the full title/result context/filter/search composition into scroll content. Let the pinned header reveal only a compact grouped Liquid Glass row after meaningful scroll. Keep the native search-role tab, lazy grid, stable item IDs, poster geometry, and selection transition source.

- [ ] **Step 5: Update tvOS controls and activation**

Place adjacent filter/sort controls in one stable native glass container. Keep resting posters artwork-only and focused poster glass/rim geometry fixed. Remove the 105 ms sleep in `TVLibraryPosterCard.handleActivation()`; start press feedback and invoke `onSelect()` in the same event turn.

- [ ] **Step 6: Validate Library suites and tvOS build**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:PlaybackEngineTests/LibraryViewModelTests \
  -only-testing:PlaybackEngineTests/LibraryEditorialLayoutTests \
  -only-testing:PlaybackEngineTests/TVUXPolishNavigationTests
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'
```

---

## Task 7: Reduce Detail render cost, then apply Glass+ hierarchy

**Files:**

- Modify: `ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Detail/TVDetailHeroChromeLayout.swift`
- Modify: `Tests/PlaybackEngineTests/IOSDetailCarouselLayoutTests.swift`
- Modify: `Tests/PlaybackEngineTests/TVDetailViewModelTests.swift`
- Modify: `Tests/PlaybackEngineTests/TVUXPolishLayoutTests.swift`

- [ ] **Step 1: Add failing Detail cost and geometry tests**

Assert selected entries budget exactly one hero stack, neighbor entries use the preview profile, scroll presentation buckets are stable across small raw-offset changes, shadow radius is constant inside each state, Play remains tvOS initial focus, and transition-source identity is unchanged.

- [ ] **Step 2: Confirm RED**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:PlaybackEngineTests/IOSDetailCarouselLayoutTests \
  -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests
```

- [ ] **Step 3: Eliminate duplicate selected hero work**

In `IOSDetailTopCarouselCard`, render `selectedContent()` as the sole selected hero-grade composition. Render non-selected entries with one `CachedRemoteImage` using `.detailPreview`, a static gradient, and no `HeroBackgroundView`. Keep the existing card frames, occurrence-qualified IDs, scroll target behavior, and native zoom continuity.

- [ ] **Step 4: Quantize scroll presentation**

Convert raw `IOSDetailScrollSnapshot` into a small Equatable presentation snapshot before storing it. Keep only visually necessary continuous transforms isolated to the top stage. Use fixed shadow radii and animate opacity/small transforms only.

- [ ] **Step 5: Apply editorial action hierarchy**

Use shared logo-first identity and grouped native glass for Back/Share/More and Play/Favorite/completion actions. Maintain neutral-white primary action contrast, champagne kickers/progress, readable synopsis, and lazy supporting rows. On tvOS preserve inline hosting, event-driven dismissal, exact source return, and Play-first focus; remove non-actionable cast nodes from focus participation unless they execute a real action.

- [ ] **Step 6: Validate Detail/navigation/playback entry tests**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:PlaybackEngineTests/IOSDetailCarouselLayoutTests \
  -only-testing:PlaybackEngineTests/TVDetailViewModelTests \
  -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests \
  -only-testing:PlaybackEngineTests/PlaybackTransportStateTests
```

---

## Task 8: Regenerate, test both platforms, and run simulator journeys

**Files:**

- Modify only if evidence requires: affected source/test files from Tasks 1–7
- Create artifacts under ignored `.artifacts/` or `.superpowers/`; do not commit simulator state or logs

- [ ] **Step 1: Regenerate and build exact configured destinations**

```bash
xcodegen generate
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'
```

- [ ] **Step 2: Run complete unit/UI schemes**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'
```

If an existing environment-dependent UI test cannot run, capture the exact failure and still run all unit targets plus the relevant manual journey. Do not describe a skipped test as passing.

- [ ] **Step 3: Exercise iOS in Simulator**

Run authenticated cold/warm Home, manual/automatic carousel, background/foreground, fast rails, rapid Library typing/filter/sort/pagination overlap, expanded-to-compact header, Home/Library Detail entry and exact return, Detail carousel/supporting rows, bright/dark art, image fallback, Reduce Motion, Reduce Transparency, and VoiceOver labels. Capture Home, compact Library, and Detail screenshots.

- [ ] **Step 4: Exercise tvOS in Simulator**

Traverse Home and Library quickly, verify one focus transition per input, immediate poster activation, every first-row route, inline Detail Play-first focus, exact source return, playback launch/dismissal, Reduce Motion, Reduce Transparency, and focused/resting pairs over bright/dark artwork. Capture screenshots.

- [ ] **Step 5: Run performance probes**

```bash
scripts/run_player_ui_probe.sh
scripts/run_playback_qa_loop.sh
python3 scripts/test_tvos_profile.py
```

Also capture comparative SwiftUI body updates, Animation Hitches, Time Profiler samples around ImageIO/layout/material work, peak decoded-image memory, and image request/dedupe/cancellation signposts for the same journeys where local tooling permits.

---

## Task 9: Record evidence and perform completion audit

**Files:**

- Modify: `PLANS.md`
- Modify: `OPTIMIZATION_AUDIT.md`
- Modify: `Docs/superpowers/specs/2026-07-26-cinematic-editorial-ui-redesign-design.md`
- Modify: this plan file to mark completed checkboxes

- [ ] **Step 1: Record actual results, not intentions**

Add exact commands, destinations, pass/fail counts, simulator journeys, screenshots/artifact paths, before/after performance observations, and any known limitations. Record artwork/focus/playback findings required by AGENTS.md.

- [ ] **Step 2: Inspect the final diff and tree**

```bash
git status --short
git diff --stat
git diff --check
git diff -- ReelFinUI ImageCache Shared Tests PLANS.md OPTIMIZATION_AUDIT.md Docs/superpowers
```

- [ ] **Step 3: Run the final verification commands fresh**

Do not rely on earlier output. Re-run generation, both builds, the complete viable tests, and the highest-risk Home/Library/Detail/focus/image suites immediately before claiming completion.

- [ ] **Step 4: Self-review against acceptance criteria**

Confirm all of the following with evidence: consistent editorial identity, clean native Glass+ without card-wall overuse, no auto haptic, latest-wins Library, canonical/bounded/authenticated artwork, stale-publication guard, one selected Detail hero stack, cheap previews, immediate tvOS activation, exact focus return, accessible fallbacks, and no launch/playback regressions.
