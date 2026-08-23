# Native Liquid Glass Player Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a functional, adaptive iOS/tvOS custom player chrome that matches the supplied Apple-style references and never displays an unconnected control.

**Architecture:** Keep the Apple playback renderers unchanged and place one capability-driven interaction contract above them. Implement separate iOS and tvOS SwiftUI presentations over that contract, with a shared confirmed/pending track-selection state and platform-native Liquid Glass/focus behavior.

**Tech Stack:** Swift 6, SwiftUI, AVKit, MediaPlayer, Observation, XCTest, XcodeGen, iOS 26/tvOS 26 SDKs.

**Spec:** `Docs/superpowers/specs/2026-08-23-native-liquid-glass-player-redesign.md`

## Global Constraints

- Keep playback Apple-native; do not add third-party media engines or private playback APIs.
- A visible button must dispatch a real action; unavailable PiP/share actions remain absent.
- Track changes remain visibly pending until the active playback state confirms the request.
- iOS custom chrome must hide/reveal immediately on background tap and remain adaptive in landscape.
- tvOS remote ownership and focus remain singular and deterministic, without fixed sleeps as the primary handoff.
- Update `project.yml` first only if target membership changes; regenerate the project after adding Swift files.
- Record playback hot-path changes in `PLANS.md` and `OPTIMIZATION_AUDIT.md`.

---

### Task 1: Capability-driven control inventory

**Files:**
- Create: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerChromeCapabilities.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTransportOverlayView.swift`
- Test: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`

**Interfaces:**
- Consumes: `PlaybackControlsModel` and existing `NativePlayerTVChromeAction` metadata.
- Produces: `NativePlayerChromeCapabilities`, `NativePlayerIOSTopAction`, `NativePlayerIOSBottomAction`, and ordered action arrays consumed by both platform presentations.

- [ ] **Step 1: Write failing control-inventory tests**

```swift
func testIOSChromeOmitsUnavailablePlaceholderActions() {
    let capabilities = NativePlayerChromeCapabilities(
        supportsPictureInPicture: false,
        supportsAirPlay: true,
        supportsSystemVolume: true,
        supportsShare: false,
        supportsVideoInformation: true,
        hasAudioChoices: true,
        hasSubtitleChoices: true
    )

    XCTAssertEqual(capabilities.iOSTopActions, [.airPlay])
    XCTAssertEqual(capabilities.iOSBottomActions, [.videoInformation, .audio, .subtitles])
}

func testTVChromeReferenceOrderContainsOnlyRealDestinations() {
    XCTAssertEqual(
        NativePlayerTVChromeAction.allCases,
        [.video, .subtitles, .audio, .settings]
    )
}
```

- [ ] **Step 2: Run the targeted tests and confirm the new symbols/order fail**

Run:

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests
```

Expected: compilation failure for `NativePlayerChromeCapabilities` and `.settings`, or assertion failure against the old order.

- [ ] **Step 3: Implement the capability and action types**

```swift
struct NativePlayerChromeCapabilities: Equatable {
    let supportsPictureInPicture: Bool
    let supportsAirPlay: Bool
    let supportsSystemVolume: Bool
    let supportsShare: Bool
    let supportsVideoInformation: Bool
    let hasAudioChoices: Bool
    let hasSubtitleChoices: Bool

    var iOSTopActions: [NativePlayerIOSTopAction] {
        var actions: [NativePlayerIOSTopAction] = []
        if supportsPictureInPicture { actions.append(.pictureInPicture) }
        if supportsAirPlay { actions.append(.airPlay) }
        if supportsShare { actions.append(.share) }
        return actions
    }

    var iOSBottomActions: [NativePlayerIOSBottomAction] {
        var actions: [NativePlayerIOSBottomAction] = []
        if supportsVideoInformation { actions.append(.videoInformation) }
        if hasAudioChoices { actions.append(.audio) }
        if hasSubtitleChoices { actions.append(.subtitles) }
        return actions
    }
}
```

Change the tvOS action enum to `.video`, `.subtitles`, `.audio`, `.settings`, with every destination mapped to an existing or newly defined real panel.

- [ ] **Step 4: Run the targeted tests until they pass**

Run the Task 1 command. Expected: PASS.

- [ ] **Step 5: Commit the capability contract**

```bash
git add ReelFinUI/Sources/ReelFinUI/Player/NativePlayer Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift
git commit -m "refactor: define real player chrome capabilities"
```

---

### Task 2: Confirmed and pending track transitions

**Files:**
- Create: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTrackTransition.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/TrackPickerView.swift`
- Test: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`

**Interfaces:**
- Consumes: `PlaybackControlSelection`, confirmed audio/subtitle IDs from `PlaybackTransportState`, and menu option IDs.
- Produces: `NativePlayerTrackTransitionState` with `request(_:)`, `confirm(audioID:subtitleID:)`, `failPendingRequest()`, and truthful row presentation.

- [ ] **Step 1: Write failing transition-state tests**

```swift
func testTrackTransitionStaysPendingUntilEngineConfirmation() {
    var state = NativePlayerTrackTransitionState()
    state.request(.audio("eng"))
    XCTAssertEqual(state.pendingSelection, .audio("eng"))
    XCTAssertEqual(state.status(for: .audio("eng")), .pending)

    state.confirm(audioID: "fra", subtitleID: nil)
    XCTAssertEqual(state.status(for: .audio("eng")), .pending)

    state.confirm(audioID: "eng", subtitleID: nil)
    XCTAssertNil(state.pendingSelection)
    XCTAssertEqual(state.status(for: .audio("eng")), .selected)
}

func testLatestTrackRequestWinsAndFailureRestoresConfirmedSelection() {
    var state = NativePlayerTrackTransitionState(confirmedAudioID: "fra")
    state.request(.audio("eng"))
    state.request(.audio("deu"))
    state.failPendingRequest()
    XCTAssertNil(state.pendingSelection)
    XCTAssertEqual(state.status(for: .audio("fra")), .selected)
    XCTAssertEqual(state.failureMessage, "Impossible de changer la piste")
}
```

- [ ] **Step 2: Run the targeted tests and confirm failure**

Run the Task 1 test command. Expected: compilation failure for `NativePlayerTrackTransitionState`.

- [ ] **Step 3: Implement the value-state machine**

```swift
struct NativePlayerTrackTransitionState: Equatable {
    enum RowStatus: Equatable { case idle, selected, pending }

    private(set) var confirmedAudioID: String?
    private(set) var confirmedSubtitleID: String?
    private(set) var pendingSelection: PlaybackControlSelection?
    private(set) var failureMessage: String?

    init(confirmedAudioID: String? = nil, confirmedSubtitleID: String? = nil) {
        self.confirmedAudioID = confirmedAudioID
        self.confirmedSubtitleID = confirmedSubtitleID
    }

    mutating func request(_ selection: PlaybackControlSelection) {
        pendingSelection = selection
        failureMessage = nil
    }

    mutating func confirm(audioID: String?, subtitleID: String?) {
        confirmedAudioID = audioID
        confirmedSubtitleID = subtitleID
        if pendingSelection == .audio(audioID ?? "") || pendingSelection == .subtitle(subtitleID) {
            pendingSelection = nil
        }
    }

    mutating func failPendingRequest() {
        guard pendingSelection != nil else { return }
        pendingSelection = nil
        failureMessage = "Impossible de changer la piste"
    }
}
```

Implement `status(for:)` without treating `nil` audio as a valid selection. Keep request replacement latest-wins.

- [ ] **Step 4: Integrate pending feedback into both menu presentations**

Pass a `NativePlayerTrackTransitionState` into the menu views. Render `ProgressView()` for the pending row, a checkmark only for confirmed selection, and `Text("Changement…")` near the menu title while pending. Keep the panel open until confirmation; schedule one cancelable 12-second failure task per request.

- [ ] **Step 5: Run tests and commit**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests
git add ReelFinUI/Sources/ReelFinUI/Player Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift
git commit -m "fix: expose confirmed player track transitions"
```

Expected: targeted tests PASS.

---

### Task 3: Reference-matched adaptive iOS chrome

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerIOSTransportOverlayView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerIOSGlassControls.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerIOSSystemControls.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerIOSTimelineView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/TrackPickerView.swift`
- Test: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`

**Interfaces:**
- Consumes: `NativePlayerChromeCapabilities`, real action closures, playback presentation, and track transition state.
- Produces: the landscape iOS chrome and anchored menus shown in references 1–4.

- [ ] **Step 1: Write failing adaptive-layout tests**

```swift
func testIOSChromeReferenceMetricsRemainUsableOnCompactLandscape() {
    let regular = NativePlayerIOSChromeLayout.metrics(width: 932, height: 430)
    let compact = NativePlayerIOSChromeLayout.metrics(width: 667, height: 375)

    XCTAssertGreaterThanOrEqual(regular.minimumHitTarget, 44)
    XCTAssertGreaterThanOrEqual(compact.minimumHitTarget, 44)
    XCTAssertGreaterThan(regular.primaryTransportDiameter, regular.transportDiameter)
    XCTAssertLessThanOrEqual(compact.horizontalPadding, regular.horizontalPadding)
    XCTAssertGreaterThan(compact.timelineHeight, 0)
}
```

- [ ] **Step 2: Run the test and confirm the layout type is missing**

Run the Task 1 test command. Expected: compilation failure for `NativePlayerIOSChromeLayout`.

- [ ] **Step 3: Implement geometry and Liquid Glass grouping**

Create `NativePlayerIOSChromeLayout.metrics(width:height:)` in the overlay file. Use one `GlassEffectContainer` for the top-leading controls, one for center transport, and one for bottom actions. Apply `.glassEffect(.regular.interactive(), in:)` after sizing/padding and use an opaque dark fallback when `accessibilityReduceTransparency` is true.

- [ ] **Step 4: Replace the fake top control inventory**

Render close separately. Render PiP/share only when a non-nil real closure and matching capability are supplied. Keep `AVRoutePickerView` and `MPVolumeView` as the real AirPlay/volume implementations. Add the real video-information action to the lower group.

- [ ] **Step 5: Match the title/timeline/menu composition**

Place the title row directly above a full-width glass timeline capsule. Anchor the menu to the trailing edge above the lower controls. Reuse the subtitle root hierarchy from `NativePlayerAVKitMenuView`, but select iOS metrics capped to the available height and width.

- [ ] **Step 6: Verify hide/reveal and all buttons in UI tests**

Run:

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:ReelFinUITests
```

Expected: the existing player identifiers remain discoverable; close, play/pause, both seeks, audio, subtitles, video information, background hide, and background reveal execute once.

- [ ] **Step 7: Commit the iOS chrome**

```bash
git add ReelFinUI/Sources/ReelFinUI/Player Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift
git commit -m "feat: rebuild adaptive iOS liquid glass player chrome"
```

---

### Task 4: Use the same custom chrome on the custom AVPlayer route

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`
- Modify: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`

**Interfaces:**
- Consumes: `NativePlayerIOSTransportOverlayView`, the custom engine's player/track APIs, `customPlaybackControls`, and the shared track-transition state.
- Produces: one consistent iOS custom-player experience for both custom AVPlayer and native sample-buffer routes.

- [ ] **Step 1: Replace the old system-control policy test**

```swift
func testCustomPlayerIOSOwnsOneCustomChromeWithoutAVKitDuplicate() {
    XCTAssertTrue(CustomPlayerIOSChromePolicy.showsReelFinChrome)
    XCTAssertFalse(CustomPlayerIOSChromePolicy.showsAVKitPlaybackControls)
}
```

- [ ] **Step 2: Run the targeted test and confirm failure**

Run the Task 1 test command. Expected: compilation failure for `CustomPlayerIOSChromePolicy`.

- [ ] **Step 3: Add iOS chrome state and routing to `CustomPlayerView`**

Define `isIOSChromeVisible`, `activeIOSTrackMenu`, and one cancelable auto-hide task outside the tvOS compilation block. Bind play/pause to `engine.togglePlayPause()`, seek to `engine.seek(toSeconds:)`, and track selections to `engine.selectAudioTrack(id:)` / `engine.subtitles.select(trackID:)`.

- [ ] **Step 4: Disable duplicate AVKit controls on the custom route**

```swift
enum CustomPlayerIOSChromePolicy {
    static let showsReelFinChrome = true
    static let showsAVKitPlaybackControls = false
}
```

Set `AVPlayerViewController.showsPlaybackControls` from that policy. Do not change the legacy AVKit route in `PlayerView`; it remains the system-native fallback.

- [ ] **Step 5: Run targeted tests and commit**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests
git add ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift
git commit -m "feat: unify custom iOS player chrome"
```

Expected: PASS.

---

### Task 5: Reference-matched tvOS chrome and focus graph

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTransportOverlayView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerChromePresentation.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerRemoteInputLayer.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTimelineView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`
- Test: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`
- Test: `Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift`

**Interfaces:**
- Consumes: the shared actions/capabilities, current tvOS command dispatcher, and existing AVKit-style menu state.
- Produces: four-action lower-trailing chrome, real down-for-info behavior, anchored popovers, and one updated focus graph.

- [ ] **Step 1: Write failing reference-geometry and focus tests**

```swift
func testTVChromeUsesReferenceControlClusterAndNoUtilityRow() {
    let layout = NativePlayerTVChromeLayout.standard
    XCTAssertEqual(layout.circleDiameter, 62)
    XCTAssertEqual(layout.actionClusterAlignment, .bottomTrailing)
    XCTAssertFalse(layout.showsUtilityRow)
}

func testTVFocusMovesBetweenTimelineAndFourVisibleActions() {
    let actions = NativePlayerTVChromeAction.allCases
    XCTAssertEqual(
        NativePlayerTVChromeFocusGraph.destination(from: .timeline, direction: .up, availableActions: actions),
        .video
    )
    XCTAssertEqual(
        NativePlayerTVChromeFocusGraph.destination(from: .settings, direction: .left, availableActions: actions),
        .audio
    )
}
```

- [ ] **Step 2: Run tvOS targeted tests and confirm failure**

Run:

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests
```

Expected: compilation/assertion failure for the new layout fields/action.

- [ ] **Step 3: Recompose the tvOS lower chrome**

Remove the utility-pill row. Place metadata lower-leading, four 62-point circular controls lower-trailing, and the timeline below both. Keep info/details/continue as rows in the settings destination so all existing behavior remains reachable.

- [ ] **Step 4: Implement the real down-for-info route**

When chrome is hidden, `.move(.down)` reveals chrome and requests `.settings`; when chrome is visible and focus is on the timeline, down opens the settings panel. The top-center hint is shown only while this route is available.

- [ ] **Step 5: Update menu anchoring and focus styling**

Anchor audio/subtitle/settings cards above the selected action cluster. Preserve the AVKit-style white focused row, single `FocusState`, and Menu precedence. Do not add delayed focus work beyond actor-turn `Task.yield()` reconciliation already used by the project.

- [ ] **Step 6: Run tvOS policy and live UI tests**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:ReelFinTVUITests/TVPlayerLiveUserJourneyTests
```

Expected: policy/layout and focus journeys PASS.

- [ ] **Step 7: Commit the tvOS chrome**

```bash
git add ReelFinUI/Sources/ReelFinUI/Player Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift
git commit -m "feat: match tvOS player chrome references"
```

---

### Task 6: Compact cross-platform resume/restart decision

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/PlaybackResumeChoiceView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`
- Modify: `Tests/PlaybackEngineTests/TVUXPolishLayoutTests.swift`
- Modify: `Tests/PlaybackEngineTests/DetailViewModelActionTests.swift`
- Test: `Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift`

**Interfaces:**
- Consumes: `PlaybackLaunchEntryRouter.presentationIntent`, saved position ticks, and existing select/cancel closures.
- Produces: one adaptive `PlaybackResumeChoiceView` presented before session creation on iOS and tvOS.

- [ ] **Step 1: Write failing compact vertical-layout tests**

```swift
func testResumeChoiceMatchesCompactVerticalReference() {
    let layout = PlaybackResumeChoiceLayout.tvOS
    XCTAssertEqual(layout.axis, .vertical)
    XCTAssertLessThanOrEqual(layout.maxWidth, 540)
    XCTAssertEqual(layout.buttonHeight, 72)
    XCTAssertEqual(PlaybackLaunchChoicePolicy.defaultFocusedChoice, .resume)
}
```

- [ ] **Step 2: Run the targeted layout tests and confirm failure**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests
```

Expected: compilation failure for `PlaybackResumeChoiceLayout` or assertion failure against the horizontal 760-point layout.

- [ ] **Step 3: Make the decision view cross-platform and vertical**

Replace the horizontal button row with a vertical stack. Use `PlaybackResumeChoiceLayout.iOS` and `.tvOS`; keep a compact continuous glass card, timestamped resume title, default resume focus on tvOS, and a cancel path that does not emit a launch request.

- [ ] **Step 4: Present the intent on iOS before the full-screen player**

Set `presentsExplicitChoice = true` for movies/episodes on iOS. Overlay the choice view when `playbackLaunchRouter.presentationIntent != nil`, disable underlying detail/home interaction, and create `playerPresentation` only after selection.

- [ ] **Step 5: Run policy and UI tests, then commit**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/DetailViewModelActionTests -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:ReelFinTVUITests/TVPlayerLiveUserJourneyTests
git add ReelFinUI/Sources/ReelFinUI/Player/PlaybackResumeChoiceView.swift ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift Tests
git commit -m "feat: add compact cross-platform resume choice"
```

Expected: PASS.

---

### Task 7: Project validation, visual evidence, and audit notes

**Files:**
- Modify: `PLANS.md`
- Modify: `OPTIMIZATION_AUDIT.md`
- Regenerate: `ReelFin.xcodeproj`
- Create: `.artifacts/player-reference-validation/ios-player.png`
- Create: `.artifacts/player-reference-validation/tvos-player.png`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: reproducible build/test evidence and simulator screenshots; `.artifacts` remains untracked.

- [ ] **Step 1: Regenerate the project**

```bash
xcodegen generate
```

Expected: exit 0.

- [ ] **Step 2: Run iOS and tvOS builds**

```bash
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'
```

Expected: both `BUILD SUCCEEDED`.

- [ ] **Step 3: Run targeted tests and player probes**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests -only-testing:PlaybackEngineTests/DetailViewModelActionTests
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests -only-testing:ReelFinTVUITests/TVPlayerLiveUserJourneyTests
scripts/run_player_ui_probe.sh
scripts/run_playback_qa_loop.sh
```

Expected: tests PASS. If a live server fixture is unavailable, record the exact skipped/failed prerequisite separately from code failures.

- [ ] **Step 4: Capture and inspect simulator screenshots**

Boot the configured iPhone and Apple TV simulators, launch the relevant UI-test fixture, reveal chrome, and capture screenshots to `.artifacts/player-reference-validation/`. Compare control order, panel anchoring, title/progress geometry, focus treatment, and glass grouping against the supplied references.

- [ ] **Step 5: Update audit documents with measured evidence**

Append a dated entry to both documents listing changed hot paths, test commands/results, simulator runtimes, interaction evidence, and any fixture-only limitation.

- [ ] **Step 6: Run the complete test suites**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'
```

Expected: all local deterministic tests PASS.

- [ ] **Step 7: Commit validation records**

```bash
git add PLANS.md OPTIMIZATION_AUDIT.md ReelFin.xcodeproj
git commit -m "test: validate liquid glass player redesign"
```

Do not add `.artifacts` screenshots to git.

## Completion Record — 2026-08-23

- Tasks 1–6 completed and committed on `main` in focused commits.
- Task 7 completed with XcodeGen, explicit iOS/tvOS 26.5 builds, 1,117 iOS playback-engine tests (9 external skips, 0 failures), 27 image-cache tests (0 failures), 18 tvOS tests (0 failures), a passing deterministic iOS interaction/capture test, and a passing hermetic tvOS hidden-chrome Down → Settings → focused Info → Info-panel journey using production components.
- The final inspected captures are `.artifacts/player-reference-validation-ios-final/E5431C02-EC4B-4786-966E-2480A09A1A0F.png` and `.artifacts/player-reference-validation-tvos-final/CA945A34-E772-4D29-AFA9-35B3C41F2534.png`; artifacts remain untracked.
- The live probe was attempted but its two explicit external Jellyfin fixture IDs were not visible in the simulator account, so no fresh live-server result is claimed.
