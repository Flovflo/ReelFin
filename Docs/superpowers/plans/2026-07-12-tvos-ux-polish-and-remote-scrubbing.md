# tvOS UX Polish And Circular Remote Scrubbing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tvOS focus, Home/Library-to-Detail navigation, Back behavior, Resume/loading surfaces, and custom-player timeline interaction feel unmistakable, compact, fluid, and native to the Siri Remote.

**Architecture:** Extend ReelFin's existing tvOS motion tokens with explicit focus geometry, add a pure detail/back state coordinator shared by Home and Library, and centralize compact launch metrics. Implement circular clickpad scrubbing as a pure angle/session policy plus one public UIKit indirect-pan adapter, then wire it through the shared player timeline into both CustomPlayer and NativePlayer without changing iOS.

**Tech Stack:** Swift 6, SwiftUI, UIKit `UIPanGestureRecognizer`, tvOS 27 Liquid Glass, AVFoundation, XCTest/XCUITest, XcodeGen.

## Global Constraints

- Keep playback Apple-native; add no third-party media engine, gesture package, or private tvOS API.
- Preserve Resume/Restart exact-once behavior, seek-to-zero reliability, Jellyfin progress reporting, and authenticated simulator state.
- iOS must retain its current player, focus-free layouts, compact subtitles, and launch presentation.
- Focused Home poster scale is `1.07`; focused Home landscape scale is `1.06`; focused Library poster scale is `1.06`.
- Library first-row focus reserve is at least `34` points plus computed scale overflow.
- Detail opening duration is `0.34` seconds; closing duration is `0.30` seconds; repeated Back during closing is consumed.
- Back precedence is Resume popup → player panel/menu → player → Detail → root/system exit.
- Resume card maximum width is `760`, radius `34`, padding `44/34`, button height `66`, focus wash `0.20`.
- Player launch card maximum width is `420`, radius `24`, padding `20/16`, spinner `34`, progress width `280`.
- Circular scrub target is always clamped to `[0, duration]`, preview creates no seek backlog, Select commits once, and Back cancels once.
- Do not reset, uninstall, sign out, or use a physical Apple TV; use simulator `092D088B-6307-4EFB-AE53-2457C2EE7F1A`.
- New focus/warmup/gesture work is latest-wins, cancelable, and uses no fixed sleep as its primary handoff.

---

### Task 1: Stronger Home/Library Focus And First-Row Overflow

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Theme/ReelFinTheme.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Library/TVLibraryPosterCard.swift`
- Create: `Tests/PlaybackEngineTests/TVUXPolishLayoutTests.swift`

**Interfaces:**
- Produces: `TVFocusGeometry`, new `TVMotion.FocusRole.homePosterCard` and `.homeLandscapeCard`, and `TVLibraryFocusLayout.firstRowTopReserve`.
- Consumes: existing `TVMotionFocusModifier`, `TVHomeShelfCard.layoutStyle`, and `TVLibraryPosterCard` focus state.

- [ ] **Step 1: Write failing focus-geometry tests**

Add tests equivalent to:

```swift
func testTVFocusScalesMatchApprovedCouchDistanceGeometry() {
    XCTAssertEqual(TVFocusGeometry.scale(for: .homePosterCard, reduceMotion: false), 1.07)
    XCTAssertEqual(TVFocusGeometry.scale(for: .homeLandscapeCard, reduceMotion: false), 1.06)
    XCTAssertEqual(TVFocusGeometry.scale(for: .libraryPoster, reduceMotion: false), 1.06)
    XCTAssertEqual(TVFocusGeometry.scale(for: .homePosterCard, reduceMotion: true), 1.02)
}

func testLibraryFirstRowReserveContainsScaleOverflowAndShadow() {
    let reserve = TVLibraryFocusLayout.firstRowTopReserve(
        cardWidth: 240,
        scale: 1.06,
        minimumReserve: 34
    )
    XCTAssertGreaterThanOrEqual(reserve, 34 + ((240 * 1.06 - 240) / 2))
}
```

- [ ] **Step 2: Run RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests
```

Expected: compile failure because `TVFocusGeometry` and `TVLibraryFocusLayout` do not exist.

- [ ] **Step 3: Implement pure geometry and role-specific focus**

Add an internal policy in `ReelFinTheme.swift`:

```swift
enum TVFocusGeometry {
    static let focusedStrokeOpacity = 0.31
    static let focusedStrokeWidth: CGFloat = 1.4
    static let focusedShadowOpacity = 0.48
    static let focusedShadowRadius: CGFloat = 34
    static let focusedShadowY: CGFloat = 18

    static func scale(for role: TVMotion.FocusRole, reduceMotion: Bool) -> CGFloat {
        if reduceMotion { return 1.02 }
        switch role {
        case .homePosterCard: 1.07
        case .homeLandscapeCard, .libraryPoster: 1.06
        case .posterCard: 1.04
        case .heroButton, .chip, .episodeCard: 1.03
        case .navItem: 1
        }
    }
}

enum TVLibraryFocusLayout {
    static func firstRowTopReserve(
        cardWidth: CGFloat,
        scale: CGFloat,
        minimumReserve: CGFloat = 34
    ) -> CGFloat {
        minimumReserve + max(0, (cardWidth * scale - cardWidth) / 2)
    }
}
```

Read `accessibilityReduceMotion` in the modifier environment and use the policy. Home chooses `.homeLandscapeCard` for `.landscape` and `.homePosterCard` otherwise. Library uses `.libraryPoster` and the shared focused stroke/shadow metrics.

- [ ] **Step 4: Reserve focus overflow in both scroll surfaces**

In Library, apply the calculated top margin to scroll content rather than padding every card:

```swift
.contentMargins(
    .top,
    TVLibraryFocusLayout.firstRowTopReserve(cardWidth: 240, scale: 1.06),
    for: .scrollContent
)
```

Increase Home's rail vertical focus reserve without changing section data order. Ensure the scale transform remains centered and metadata is not clipped.

- [ ] **Step 5: Run GREEN and builds**

Run the Task 1 focused test command, then build `ReelFinTV` for simulator `092D088B-6307-4EFB-AE53-2457C2EE7F1A`. Expected: all pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add ReelFinUI/Sources/ReelFinUI/Theme/ReelFinTheme.swift \
  ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift \
  ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift \
  ReelFinUI/Sources/ReelFinUI/Library/TVLibraryPosterCard.swift \
  Tests/PlaybackEngineTests/TVUXPolishLayoutTests.swift ReelFin.xcodeproj/project.pbxproj
git commit -m "feat(tvos): strengthen Home and Library focus"
```

---

### Task 2: Shared Detail Transition And Back Ownership

**Files:**
- Create: `ReelFinUI/Sources/ReelFinUI/TV/TVDetailPresentationCoordinator.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift`
- Create: `Tests/PlaybackEngineTests/TVUXPolishNavigationTests.swift`
- Modify: `Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift`

**Interfaces:**
- Produces: `TVDetailPresentationPhase`, `TVDetailPresentationCoordinator`, `TVBackNavigationOwner`, and `TVDetailTransitionMetrics`.
- Consumes: existing Home/Library transition namespaces, source IDs, selected item state, and Detail `onDismissRequest`.

- [ ] **Step 1: Write failing state/back tests**

```swift
func testDetailBackIsConsumedUntilClosingCompletes() {
    var state = TVDetailPresentationCoordinator()
    state.beginOpening(itemID: "dexter", sourceID: "home-row-dexter")
    state.finishOpening()
    XCTAssertEqual(state.handleBack(), .beginClosing)
    XCTAssertEqual(state.handleBack(), .consumedWhileClosing)
    XCTAssertTrue(state.keepsDetailMounted)
    state.finishClosing()
    XCTAssertEqual(state.phase, .idle)
}

func testBackPrecedenceReturnsInsideAppBeforeSystemExit() {
    XCTAssertEqual(TVBackNavigationPolicy.action(for: .resumeChoice), .cancelResumeChoice)
    XCTAssertEqual(TVBackNavigationPolicy.action(for: .playerPanel), .closePlayerPanel)
    XCTAssertEqual(TVBackNavigationPolicy.action(for: .player), .closePlayer)
    XCTAssertEqual(TVBackNavigationPolicy.action(for: .detail), .closeDetail)
    XCTAssertEqual(TVBackNavigationPolicy.action(for: .root), .allowSystemExit)
}
```

- [ ] **Step 2: Verify RED**

Run `TVUXPolishNavigationTests`; expected compile failure for missing coordinator/policy.

- [ ] **Step 3: Implement the pure coordinator**

```swift
enum TVDetailPresentationPhase: Equatable, Sendable {
    case idle
    case opening(itemID: String, sourceID: String?)
    case presented(itemID: String, sourceID: String?)
    case closing(itemID: String, sourceID: String?)
}

struct TVDetailPresentationCoordinator: Equatable, Sendable {
    private(set) var phase: TVDetailPresentationPhase = .idle
    var keepsDetailMounted: Bool { phase != .idle }

    mutating func beginOpening(itemID: String, sourceID: String?) {
        guard phase == .idle else { return }
        phase = .opening(itemID: itemID, sourceID: sourceID)
    }

    mutating func finishOpening() {
        guard case let .opening(itemID, sourceID) = phase else { return }
        phase = .presented(itemID: itemID, sourceID: sourceID)
    }

    mutating func handleBack() -> TVDetailBackResult {
        switch phase {
        case let .opening(itemID, sourceID), let .presented(itemID, sourceID):
            phase = .closing(itemID: itemID, sourceID: sourceID)
            return .beginClosing
        case .closing:
            return .consumedWhileClosing
        case .idle:
            return .allowRoot
        }
    }

    mutating func finishClosing() {
        guard case .closing = phase else { return }
        phase = .idle
    }
}

enum TVDetailBackResult: Equatable, Sendable {
    case beginClosing
    case consumedWhileClosing
    case allowRoot
}

enum TVBackNavigationOwner: Equatable, Sendable {
    case resumeChoice
    case playerPanel
    case player
    case detail
    case root
}

enum TVBackNavigationAction: Equatable, Sendable {
    case cancelResumeChoice
    case closePlayerPanel
    case closePlayer
    case closeDetail
    case allowSystemExit
}

enum TVBackNavigationPolicy {
    static func action(for owner: TVBackNavigationOwner) -> TVBackNavigationAction {
        switch owner {
        case .resumeChoice: .cancelResumeChoice
        case .playerPanel: .closePlayerPanel
        case .player: .closePlayer
        case .detail: .closeDetail
        case .root: .allowSystemExit
        }
    }
}

enum TVDetailTransitionMetrics {
    static let openingDuration = 0.34
    static let closingDuration = 0.30
    static let reducedMotionDuration = 0.18
}
```

Transitions are invalid from the wrong phase and repeated Back while closing returns `.consumedWhileClosing`.

- [ ] **Step 4: Integrate the stable Home detail host**

Home must not nil `selectedItem` during the Back event. Start the closing animation by changing coordinator phase, keep Detail mounted, and clear `selectedItem` only in animation completion:

```swift
guard detailPresentation.handleBack() == .beginClosing else { return }
withAnimation(detailCloseAnimation, completionCriteria: .logicallyComplete) {
    detailPresentationVisualState = .closing
} completion: {
    viewModel.dismissDetail()
    detailPresentation.finishClosing()
    homeReturnRequest &+= 1
}
```

Remove cleanup sleeps used only to approximate transition completion. Keep source-card focus disabled while `keepsDetailMounted` is true.

- [ ] **Step 5: Replace Library's tvOS navigation destination with the same stable inline host**

Keep iOS `navigationDestination` unchanged. On tvOS, Library renders Detail as an overlay using its namespace/source ID and passes an explicit `onDismissRequest`. Save the selected poster ID, disable the grid during presentation, and restore that ID after closing. Add the same reverse artwork/fade transition and reduced-motion fallback as Home.

- [ ] **Step 6: Make Detail Back exact-once**

Detail's tvOS `.onExitCommand` calls only its explicit dismiss callback. The parent coordinator owns removal. Add a DEBUG marker with enum-like values (`detail`, `closing`, `root`) and no media IDs.

- [ ] **Step 7: Run tests and targeted live Back journeys**

Add XCUIRemote flows:

- Home card → Detail → Back → exact Home card focused, app foreground.
- Library poster → Detail → Back → exact Library poster focused, app foreground.
- Two rapid Back presses during close do not exit the app.

Run the focused unit suite, tvOS UI journeys, and both platform builds.

- [ ] **Step 8: Commit Task 2**

```bash
git add ReelFinUI/Sources/ReelFinUI/TV/TVDetailPresentationCoordinator.swift \
  ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift \
  ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift \
  ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift \
  Tests/PlaybackEngineTests/TVUXPolishNavigationTests.swift \
  Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift ReelFin.xcodeproj/project.pbxproj
git commit -m "fix(tvos): keep Back inside ReelFin detail navigation"
```

---

### Task 3: Compact Liquid Glass Resume And Player Preparation

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/PlaybackResumeChoiceView.swift`
- Create: `ReelFinUI/Sources/ReelFinUI/Player/TVPlayerLaunchLayout.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`
- Modify: `Tests/PlaybackEngineTests/TVUXPolishLayoutTests.swift`
- Modify: `Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift`

**Interfaces:**
- Produces: `TVPlaybackResumeChoiceLayout.standard` and `TVPlayerLaunchLayout.standard`.
- Consumes: existing `PlaybackLaunchChoicePolicy`, `CustomPlayerLaunchPresentationPolicy`, launch context, and slow-launch actions.

- [ ] **Step 1: Write failing metric tests**

```swift
func testCompactResumeChoiceMetrics() {
    let layout = TVPlaybackResumeChoiceLayout.standard
    XCTAssertEqual(layout.maxWidth, 760)
    XCTAssertEqual(layout.cornerRadius, 34)
    XCTAssertEqual(layout.horizontalPadding, 44)
    XCTAssertEqual(layout.verticalPadding, 34)
    XCTAssertEqual(layout.buttonHeight, 66)
    XCTAssertEqual(layout.focusOpacity, 0.20)
}

func testCompactPlayerLaunchMetrics() {
    let layout = TVPlayerLaunchLayout.standard
    XCTAssertEqual(layout.maxWidth, 420)
    XCTAssertEqual(layout.cornerRadius, 24)
    XCTAssertEqual(layout.spinnerSize, 34)
    XCTAssertEqual(layout.progressWidth, 280)
    XCTAssertEqual(layout.screenInset, 64)
}
```

- [ ] **Step 2: Verify RED**

Run `TVUXPolishLayoutTests`; expected missing layout types.

- [ ] **Step 3: Implement compact Resume/Restart card**

Use one outer regular Liquid Glass card. Replace `.buttonStyle(.glass)` on tvOS with a custom `PlaybackResumeChoiceButton` whose focused background is `.white.opacity(0.20)`, focused scale `1.025`, white text, height `66`, and minimum width `270`. Keep iOS behavior unchanged behind compilation guards. Preserve all existing accessibility IDs and exact-once callbacks.

- [ ] **Step 4: Implement compact launch/cache panel**

Move metrics into `TVPlayerLaunchLayout`. Keep the backdrop and first-frame gate, but render the panel at the approved intrinsic size, spinner 34, progress width 280, and 64-point bottom-leading inset. Slow Retry/Quit remains conditional and functional. Make buffering/recovery use the same smaller glass language.

- [ ] **Step 5: Capture and validate both states**

Extend live automation to capture:

- `compact-resume-choice`
- `compact-player-preparation`
- `compact-player-buffering` when deterministically inducible without corrupting the auth/session

Reject opaque fill, full-white focus capsule, clipped labels, or cards exceeding approved metrics.

- [ ] **Step 6: Run focused tests, Resume/Restart loops, and builds**

Run layout tests, launch-choice exact-once tests, the ten-cycle live journey, and iOS/tvOS builds.

- [ ] **Step 7: Commit Task 3**

```bash
git add ReelFinUI/Sources/ReelFinUI/Player/PlaybackResumeChoiceView.swift \
  ReelFinUI/Sources/ReelFinUI/Player/TVPlayerLaunchLayout.swift \
  ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift \
  Tests/PlaybackEngineTests/TVUXPolishLayoutTests.swift \
  Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift ReelFin.xcodeproj/project.pbxproj
git commit -m "feat(tvos): compact playback launch surfaces"
```

---

### Task 4: Pure Circular Scrub Math And Session State

**Files:**
- Create: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/TVRemoteCircularScrubPolicy.swift`
- Create: `Tests/PlaybackEngineTests/TVRemoteCircularScrubPolicyTests.swift`

**Interfaces:**
- Produces: `TVRemoteScrubSample`, `TVRemoteCircularScrubPolicy`, `TVRemoteCircularScrubSession`, and `TVRemoteScrubResolution`.
- Consumes: only CoreGraphics/Foundation values; no player object or SwiftUI state.

- [ ] **Step 1: Write failing angle/pacing tests**

Cover:

```swift
func testAngleUnwrapAcrossPiMovesForwardWithoutJump()
func testClockwiseAndCounterClockwiseHaveOppositeSigns()
func testCenterDeadZoneIgnoresUnstableSamples()
func testSecondsPerRevolutionScalesAndClamps()
func testVelocityMultiplierClampsBetweenHalfAndFour()
func testTargetClampsAtZeroAndDuration()
```

Expected reference assertions:

```swift
XCTAssertEqual(TVRemoteCircularScrubPolicy.secondsPerRevolution(duration: 1_800), 60)
XCTAssertEqual(TVRemoteCircularScrubPolicy.secondsPerRevolution(duration: 14_400), 300)
XCTAssertEqual(TVRemoteCircularScrubPolicy.velocityMultiplier(radiansPerSecond: 0.2), 0.5)
XCTAssertEqual(TVRemoteCircularScrubPolicy.velocityMultiplier(radiansPerSecond: 8), 4)
```

- [ ] **Step 2: Write failing session tests**

```swift
func testCircularSessionPausesPreviewsThenCommitsOnce()
func testCircularSessionCancelRestoresOriginalTimeAndIntent()
func testCircularSessionCannotBeginWithoutFiniteDuration()
func testCircularSessionUpdateIsLatestValueNotQueuedHistory()
```

- [ ] **Step 3: Verify RED**

Run `TVRemoteCircularScrubPolicyTests`; expected compile failure for missing types.

- [ ] **Step 4: Implement the pure policy**

Use `atan2`, normalize delta into `[-π, π]`, ignore radii below the dead-zone threshold, calculate angular velocity from monotonic timestamps, and clamp all results. Never log raw samples.

Implement the policy and session with these exact semantics:

```swift
import CoreGraphics
import Foundation

struct TVRemoteScrubSample: Equatable, Sendable {
    let location: CGPoint
    let center: CGPoint
    let timestamp: TimeInterval
}

struct TVRemoteScrubResolution: Equatable, Sendable {
    let targetSeconds: Double
    let wasPlaying: Bool
}

enum TVRemoteCircularScrubPolicy {
    static let centerDeadZoneRadius: CGFloat = 18

    static func angularDelta(
        previous: TVRemoteScrubSample,
        current: TVRemoteScrubSample
    ) -> Double? {
        let previousVector = CGPoint(
            x: previous.location.x - previous.center.x,
            y: previous.location.y - previous.center.y
        )
        let currentVector = CGPoint(
            x: current.location.x - current.center.x,
            y: current.location.y - current.center.y
        )
        guard hypot(previousVector.x, previousVector.y) >= centerDeadZoneRadius,
              hypot(currentVector.x, currentVector.y) >= centerDeadZoneRadius else {
            return nil
        }
        let previousAngle = atan2(previousVector.y, previousVector.x)
        let currentAngle = atan2(currentVector.y, currentVector.x)
        var delta = currentAngle - previousAngle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        return delta
    }

    static func secondsPerRevolution(duration: Double) -> Double {
        min(max(duration / 30, 30), 300)
    }

    static func velocityMultiplier(radiansPerSecond: Double) -> Double {
        switch abs(radiansPerSecond) {
        case ..<0.6: 0.5
        case ..<2.2: 1
        case ..<4.0: 2
        default: 4
        }
    }

    static func target(
        original: Double,
        weightedRadians: Double,
        duration: Double
    ) -> Double {
        let seconds = (weightedRadians / (2 * .pi)) * secondsPerRevolution(duration: duration)
        return min(max(original + seconds, 0), duration)
    }
}

struct TVRemoteCircularScrubSession: Equatable, Sendable {
    struct Preview: Equatable, Sendable {
        var originalTime: Double
        var targetTime: Double
        var duration: Double
        var wasPlaying: Bool
        var weightedRadians: Double
        var previousSample: TVRemoteScrubSample
    }

    enum Phase: Equatable, Sendable {
        case idle
        case preview(Preview)
    }

    private(set) var phase: Phase = .idle

    mutating func begin(
        sample: TVRemoteScrubSample,
        originalTime: Double,
        duration: Double,
        wasPlaying: Bool
    ) -> Bool {
        guard case .idle = phase,
              duration.isFinite, duration > 0,
              originalTime.isFinite else { return false }
        let clampedOriginal = min(max(originalTime, 0), duration)
        phase = .preview(Preview(
            originalTime: clampedOriginal,
            targetTime: clampedOriginal,
            duration: duration,
            wasPlaying: wasPlaying,
            weightedRadians: 0,
            previousSample: sample
        ))
        return true
    }

    mutating func update(_ sample: TVRemoteScrubSample) -> Double? {
        guard case var .preview(preview) = phase else { return nil }
        defer { preview.previousSample = sample; phase = .preview(preview) }
        guard let delta = TVRemoteCircularScrubPolicy.angularDelta(
            previous: preview.previousSample,
            current: sample
        ) else { return preview.targetTime }
        let elapsed = max(sample.timestamp - preview.previousSample.timestamp, 1.0 / 120.0)
        let multiplier = TVRemoteCircularScrubPolicy.velocityMultiplier(
            radiansPerSecond: delta / elapsed
        )
        preview.weightedRadians += delta * multiplier
        preview.targetTime = TVRemoteCircularScrubPolicy.target(
            original: preview.originalTime,
            weightedRadians: preview.weightedRadians,
            duration: preview.duration
        )
        return preview.targetTime
    }

    mutating func commit() -> TVRemoteScrubResolution? {
        guard case let .preview(preview) = phase else { return nil }
        phase = .idle
        return TVRemoteScrubResolution(
            targetSeconds: preview.targetTime,
            wasPlaying: preview.wasPlaying
        )
    }

    mutating func cancel() -> TVRemoteScrubResolution? {
        guard case let .preview(preview) = phase else { return nil }
        phase = .idle
        return TVRemoteScrubResolution(
            targetSeconds: preview.originalTime,
            wasPlaying: preview.wasPlaying
        )
    }
}
```

Commit/cancel return one resolution and reset to idle; a repeated call returns nil.

- [ ] **Step 5: Run GREEN and stress loops**

Run focused tests, then repeat alternating clockwise/counter-clockwise and boundary sessions at least 100 times in a deterministic unit test. Expected: no NaN, overflow, or target outside bounds.

- [ ] **Step 6: Commit Task 4**

```bash
git add ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/TVRemoteCircularScrubPolicy.swift \
  Tests/PlaybackEngineTests/TVRemoteCircularScrubPolicyTests.swift ReelFin.xcodeproj/project.pbxproj
git commit -m "feat(tvos): model circular Siri Remote scrubbing"
```

---

### Task 5: Indirect Clickpad Adapter And Player Integration

**Files:**
- Create: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/TVRemoteCircularScrubGestureView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTVProgressScrubberView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTimelineView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTransportOverlayView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerView.swift`
- Modify: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`
- Modify: `Tests/PlaybackEngineTests/TVRemoteCircularScrubPolicyTests.swift`

**Interfaces:**
- Consumes: Task 4 scrub session/policy and existing absolute-seek + paused bindings.
- Produces: `TVRemoteCircularScrubGestureView` callbacks and shared timeline commit/cancel behavior in both player routes.

- [ ] **Step 1: Write failing integration-policy tests**

Add a pure coordinator used by the view and test:

```swift
func testCircularScrubBeginPausesOnlyWhenTimelineFocused()
func testSelectCommitsOneAbsoluteSeekAndRestoresPlayingIntent()
func testBackCancelsToOriginalTimeAndDoesNotDismissPlayer()
func testLeavingTimelineCancelsActiveScrub()
func testCardinalShortcutsRemainMinus10Plus30OutsideScrub()
```

- [ ] **Step 2: Verify RED**

Run the two scrub/chrome suites; expected missing gesture coordinator/adapter interfaces.

- [ ] **Step 3: Implement the public UIKit indirect-pan adapter**

Create a transparent tvOS `UIViewRepresentable`:

```swift
let recognizer = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
recognizer.cancelsTouchesInView = false
```

The coordinator forwards `.began` and `.changed` samples using `location(in:)` and `ProcessInfo.processInfo.systemUptime`. Allow simultaneous recognition so center click still reaches the timeline Button. Expose an availability callback if indirect coordinates are not delivered.

- [ ] **Step 4: Integrate with the focused timeline**

`NativePlayerTVProgressScrubberView` overlays the adapter only when `.timeline` is focused. `NativePlayerTimelineView` owns `@State` session + preview value and receives the existing paused binding.

- On begin: snapshot time/play intent and pause.
- On update: change only preview UI.
- On Select: if active, commit exactly one absolute seek and restore prior play intent; otherwise keep existing chrome action.
- On Back: if active, cancel, restore original time/intent, keep player open.
- On focus loss/disappear: cancel safely.

The current/remaining labels use preview time during scrub. Add a restrained enlarged playhead and `Scrubbing` accessibility value; do not add a large modal.

- [ ] **Step 5: Wire both routes through the shared transport overlay**

Pass `$isPaused` through the shared overlay/timeline. CustomPlayer and NativePlayer continue using their existing absolute seek functions, so seek generation/cancellation remains route-owned. Preview must not call AVFoundation until commit/cancel.

- [ ] **Step 6: Add DEBUG live evidence without sensitive state**

Under exact live automation only, expose:

- `native_player_circular_scrub_available`
- `native_player_circular_scrub_state` values `idle`, `previewing`, `committed`, `cancelled`
- `native_player_circular_scrub_preview_bucket` as a rounded non-item-specific seconds bucket

Do not expose media IDs or URLs.

- [ ] **Step 7: Run focused tests and both builds**

Run scrub policy, chrome, seek-to-zero, and both player route tests; build iOS and tvOS. Verify the UIKit adapter compiles only for tvOS and iOS is unchanged.

- [ ] **Step 8: Commit Task 5**

```bash
git add ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/TVRemoteCircularScrubGestureView.swift \
  ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTVProgressScrubberView.swift \
  ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTimelineView.swift \
  ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTransportOverlayView.swift \
  ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift \
  ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerView.swift \
  Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift \
  Tests/PlaybackEngineTests/TVRemoteCircularScrubPolicyTests.swift ReelFin.xcodeproj/project.pbxproj
git commit -m "feat(tvos): add circular clickpad timeline scrubbing"
```

---

### Task 6: Authenticated UX Proof, Performance Audit, And Documentation

**Files:**
- Modify: `Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift`
- Modify: `Tests/PlaybackEngineTests/TVUXPolishLayoutTests.swift`
- Modify: `Tests/PlaybackEngineTests/TVUXPolishNavigationTests.swift`
- Modify: `PLANS.md`
- Modify: `OPTIMIZATION_AUDIT.md`

**Interfaces:**
- Consumes: Tasks 1–5 complete UI, markers, and policies.
- Produces: final screenshots, authenticated journeys, performance evidence, and documented Simulator limitations.

- [ ] **Step 1: Add Home/Library focus capture journey**

Use XCUIRemote to visit Home landscape + poster rows and every first-row Library position. Assert the focused accessibility value changes exactly once per move and capture:

- `home-landscape-focus`
- `home-poster-focus`
- `library-first-row-left`
- `library-first-row-middle`
- `library-first-row-right`

Reject ambiguous focus, clipping, title collision, or excessive layout jump.

- [ ] **Step 2: Add exact Back/transition journeys**

Open Detail from Home and Library, capture opening/presented/closing states, press Back, and assert the originating card is focused and the app remains foreground. Send a repeated Back during closing and prove it is consumed.

- [ ] **Step 3: Add compact launch captures and behavior proof**

Capture Resume/Restart and preparation. Assert card metrics through accessibility frames, both actions remain focusable, Cancel launches nothing, and ten alternating Resume/Restart cycles pass.

- [ ] **Step 4: Exercise circular scrub on the Simulator**

First attempt a real circular drag through the Simulator's Apple TV Remote/clickpad UI using local computer control while the timeline is focused. Observe live markers and prove clockwise preview increases, counter-clockwise decreases, Select commits, and Back cancels.

If the host Simulator does not deliver indirect touch coordinates, record that exact limitation, require `available=false`, and still prove:

- the pure 100-session scrub suite;
- cardinal `-10/+30` remote fallback;
- seek to zero and forward after the adapter is installed;
- no crash, stalled seek queue, or player error.

- [ ] **Step 5: Run performance probes**

Run:

```bash
scripts/run_player_ui_probe.sh
scripts/run_playback_qa_loop.sh
python3 scripts/test_tvos_profile.py
```

Inspect for focus latency, repeated glass layers, animation frame drops, MainActor expansion, and uncancelled tasks. Fix any release-blocking regression and re-run the affected gate.

- [ ] **Step 6: Run final verification**

```bash
xcodegen generate
git diff --check

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests \
  -only-testing:PlaybackEngineTests/TVUXPolishNavigationTests \
  -only-testing:PlaybackEngineTests/TVRemoteCircularScrubPolicyTests \
  -only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0'

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A'
```

Expected: all deterministic tests, iOS build, local tvOS tests, Home/Library/Back journeys, player seek journey, and ten-cycle journey pass with zero player errors.

- [ ] **Step 7: Update docs and commit Task 6**

Record exact counts, durations, screenshot paths, transition/focus visual verdict, performance results, circular-input availability, and the existing simulator audio/HDR limitations.

```bash
git add Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift \
  Tests/PlaybackEngineTests/TVUXPolishLayoutTests.swift \
  Tests/PlaybackEngineTests/TVUXPolishNavigationTests.swift \
  PLANS.md OPTIMIZATION_AUDIT.md
git commit -m "test(tvos): prove polished navigation and remote scrubbing"
```

---

## Final Review Checklist

- [ ] Every task has a separate implementation report and independent spec/quality review.
- [ ] Final whole-branch review has no open Critical or Important findings.
- [ ] No tracked credentials, Jellyfin identifiers, signed URLs, or headers appear in logs/markers.
- [ ] Worktree is clean and generated project matches `project.yml`.
- [ ] Authenticated tvOS simulator container remains installed and signed in.
- [ ] Branch is ready for explicit user-directed GitHub publication/merge.
