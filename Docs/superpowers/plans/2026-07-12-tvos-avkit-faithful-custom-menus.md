# tvOS AVKit-Faithful Custom Menus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ReelFin's tvOS track-list popover with a fully custom, AVKit-faithful Liquid Glass Audio/Subtitles hierarchy while preserving ReelFin playback, Jellyfin selection, seek reliability, and iOS behavior.

**Architecture:** Add a tvOS-only pure menu model/focus policy and a dedicated SwiftUI card renderer. Keep playback selection flowing through the existing `PlaybackControlsModel` and `PlaybackControlSelection`; add one shared persisted subtitle-background preference used by both ReelFin subtitle renderers. Wire the component into both CustomPlayer and NativePlayer, then prove it with deterministic tests and authenticated Star City UI journeys.

**Tech Stack:** Swift 6, SwiftUI, tvOS 26+ Liquid Glass, Observation/AppStorage, UIKit subtitle renderer, XCTest/XCUITest, XcodeGen.

## Global Constraints

- Keep the playback path Apple-native; add no third-party media engine or private AVKit API.
- The menu remains custom ReelFin UI; it only reproduces the supplied AVKit appearance.
- Use native `glassEffect` and `GlassEffectContainer`; no generic `List`, opaque black card, or fake blur.
- Card metrics at 1920×1080: width 600, corner radius 44, horizontal inset 54, vertical inset 42.
- Typography: header 30, primary 34, secondary 22; choice row 68, navigation row 108.
- Every rendered row performs a real action; unavailable controls are omitted.
- Preserve stable focus scopes, state-token/yield handoffs, Menu precedence, and exact origin restoration; no fixed sleeps.
- iOS keeps AVKit controls, the stable audio-session correction, and compact 20-point subtitle presentation.
- Live tests use only the alias `star-city-s1e1`, never credentials, URLs, tokens, user IDs, or full item IDs.
- Do not reset, uninstall, sign out, or use a physical Apple TV.

---

### Task 1: Pure AVKit Menu Model And Focus Policy

**Files:**
- Create: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuModel.swift`
- Test: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`

**Interfaces:**
- Consumes: `PlaybackControlsModel`, `PlaybackTrackOption`, `PlaybackTrackMenuKind`.
- Produces: `NativePlayerAVKitMenuPage`, `NativePlayerAVKitMenuRowID`, `NativePlayerSubtitleMenuPolicy`, `NativePlayerAVKitMenuFocusPolicy`.

- [ ] **Step 1: Write failing tests for hierarchy, fallback selection, and bounded focus**

Add tests equivalent to:

```swift
func testAVKitSubtitleRootMatchesReferenceHierarchy() {
    XCTAssertEqual(
        NativePlayerAVKitMenuPage.subtitlesRoot.rowIDs,
        [.subtitleOn, .subtitleOff, .subtitleLanguage, .subtitleStyle]
    )
}

func testSubtitleOnRestoresLastTrackThenDefaultThenForcedThenFirst() {
    let forced = PlaybackTrackOption(trackID: "forced", title: "French", badge: "Forced", iconName: nil, isSelected: false)
    let normal = PlaybackTrackOption(trackID: "normal", title: "English", badge: nil, iconName: nil, isSelected: false)
    XCTAssertEqual(NativePlayerSubtitleMenuPolicy.enabledTrackID(options: [normal, forced], lastEnabledID: "forced"), "forced")
    XCTAssertEqual(NativePlayerSubtitleMenuPolicy.enabledTrackID(options: [normal, forced], lastEnabledID: nil), "forced")
}

func testAVKitMenuFocusIsBoundedAndSubmenusReturnToRoot() {
    let rows: [NativePlayerAVKitMenuRowID] = [.subtitleOn, .subtitleOff, .subtitleLanguage, .subtitleStyle]
    XCTAssertEqual(NativePlayerAVKitMenuFocusPolicy.move(from: .subtitleOn, delta: -1, rows: rows), .subtitleOn)
    XCTAssertEqual(NativePlayerAVKitMenuFocusPolicy.move(from: .subtitleOff, delta: 1, rows: rows), .subtitleLanguage)
    XCTAssertEqual(NativePlayerAVKitMenuFocusPolicy.parent(of: .subtitleLanguages), .subtitlesRoot)
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
-destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
-only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests
```

Expected: FAIL because the four model/policy types do not exist.

- [ ] **Step 3: Implement the pure model**

Create the following API, keeping it free of SwiftUI state:

```swift
enum NativePlayerAVKitMenuPage: Equatable {
    case audio
    case subtitlesRoot
    case subtitleLanguages
    case subtitleStyles

    var rowIDs: [NativePlayerAVKitMenuRowID] {
        switch self {
        case .subtitlesRoot: [.subtitleOn, .subtitleOff, .subtitleLanguage, .subtitleStyle]
        default: []
        }
    }
}

enum NativePlayerAVKitMenuRowID: Hashable {
    case audio(String)
    case subtitleOn
    case subtitleOff
    case subtitleLanguage
    case subtitleStyle
    case subtitleTrack(String)
    case style(SubtitleBackgroundStyle)
}

enum NativePlayerSubtitleMenuPolicy {
    static func enabledTrackID(options: [PlaybackTrackOption], lastEnabledID: String?) -> String? {
        let real = options.filter { $0.trackID != nil }
        if let lastEnabledID, real.contains(where: { $0.trackID == lastEnabledID }) { return lastEnabledID }
        if let selected = real.first(where: \.isSelected)?.trackID { return selected }
        if let forced = real.first(where: { ($0.badge ?? "").localizedCaseInsensitiveContains("forc") })?.trackID { return forced }
        return real.first?.trackID
    }
}

enum NativePlayerAVKitMenuFocusPolicy {
    static func move(from current: NativePlayerAVKitMenuRowID, delta: Int, rows: [NativePlayerAVKitMenuRowID]) -> NativePlayerAVKitMenuRowID {
        guard let index = rows.firstIndex(of: current), !rows.isEmpty else { return rows.first ?? current }
        return rows[min(max(index + delta, 0), rows.count - 1)]
    }

    static func parent(of page: NativePlayerAVKitMenuPage) -> NativePlayerAVKitMenuPage? {
        switch page {
        case .subtitleLanguages, .subtitleStyles: .subtitlesRoot
        case .audio, .subtitlesRoot: nil
        }
    }
}
```

Do not log row or track identifiers.

- [ ] **Step 4: Run tests and verify GREEN**

Run the Step 2 command. Expected: all `NativePlayerChromeLayoutTests` pass.

- [ ] **Step 5: Commit Task 1**

```bash
git add ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuModel.swift \
Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift
git commit -m "feat(tvos): model AVKit-style player menus"
```

---

### Task 2: Shared Liquid Glass Card And Row Renderer

**Files:**
- Create: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/TrackPickerView.swift`
- Test: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`

**Interfaces:**
- Consumes: Task 1 page/row types and the existing `PlaybackControlsModel`.
- Produces: `NativePlayerAVKitMenuLayout.standard` and `NativePlayerAVKitMenuView` with initializer `(mode:controls:subtitleStyle:onSelect:onSelectStyle:onDismiss:)`.

- [ ] **Step 1: Write failing layout and action-mapping tests**

```swift
func testAVKitMenuLayoutMatchesApprovedReferenceMetrics() {
    let layout = NativePlayerAVKitMenuLayout.standard
    XCTAssertEqual(layout.width, 600)
    XCTAssertEqual(layout.cornerRadius, 44)
    XCTAssertEqual(layout.horizontalInset, 54)
    XCTAssertEqual(layout.verticalInset, 42)
    XCTAssertEqual(layout.headerSize, 30)
    XCTAssertEqual(layout.primarySize, 34)
    XCTAssertEqual(layout.secondarySize, 22)
    XCTAssertEqual(layout.choiceHeight, 68)
    XCTAssertEqual(layout.navigationHeight, 108)
    XCTAssertLessThanOrEqual(layout.focusOpacity, 0.22)
    XCTAssertEqual(layout.opaqueBackgroundOpacity, 0)
}

func testEveryReferenceRowMapsToARealAction() {
    XCTAssertEqual(NativePlayerAVKitMenuAction.forRow(.subtitleOn), .enableSubtitles)
    XCTAssertEqual(NativePlayerAVKitMenuAction.forRow(.subtitleOff), .disableSubtitles)
    XCTAssertEqual(NativePlayerAVKitMenuAction.forRow(.subtitleLanguage), .openLanguages)
    XCTAssertEqual(NativePlayerAVKitMenuAction.forRow(.subtitleStyle), .openStyles)
}
```

- [ ] **Step 2: Verify RED with the Task 1 test command**

Expected: FAIL because layout/view/action types are missing.

- [ ] **Step 3: Implement the card and rows**

Use this layout contract:

```swift
struct NativePlayerAVKitMenuLayout: Equatable {
    let width: CGFloat = 600
    let cornerRadius: CGFloat = 44
    let horizontalInset: CGFloat = 54
    let verticalInset: CGFloat = 42
    let headerSize: CGFloat = 30
    let primarySize: CGFloat = 34
    let secondarySize: CGFloat = 22
    let choiceHeight: CGFloat = 68
    let navigationHeight: CGFloat = 108
    let focusOpacity: Double = 0.20
    let selectedOpacity: Double = 0.045
    let opaqueBackgroundOpacity: Double = 0
    static let standard = Self()
}
```

The card modifier must be applied after layout:

```swift
.padding(.horizontal, layout.horizontalInset)
.padding(.vertical, layout.verticalInset)
.frame(width: layout.width)
.glassEffect(
    .regular.tint(.black.opacity(0.08)),
    in: .rect(cornerRadius: layout.cornerRadius)
)
.overlay {
    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
        .stroke(.white.opacity(0.14), lineWidth: 1)
}
```

Choice rows place the checkmark in a fixed leading column. Navigation rows use a `VStack` for primary/secondary text and a trailing `chevron.right`. Only the focused row receives the 0.20 white wash; selected-but-unfocused rows receive 0.045. Do not wrap each row in another `GlassEffectContainer`, because nested containers previously hid text in the rendered tvOS result.

Replace `NativePlayerTrackSelectionMenuView`'s old list body with a thin wrapper around `NativePlayerAVKitMenuView`; retain its public initializer so CustomPlayer and NativePlayer continue to compile before Task 4.

- [ ] **Step 4: Run focused tests and both builds**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
-project ReelFin.xcodeproj -scheme ReelFin \
-destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
-only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build \
-project ReelFin.xcodeproj -scheme ReelFinTV \
-destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A'
```

Expected: focused tests and tvOS build succeed.

- [ ] **Step 5: Commit Task 2**

```bash
git add ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuView.swift \
ReelFinUI/Sources/ReelFinUI/Player/TrackPickerView.swift \
Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift
git commit -m "feat(tvos): render AVKit-faithful Liquid Glass menus"
```

---

### Task 3: Functional Subtitle Style Preference

**Files:**
- Create: `Shared/Sources/Shared/SubtitleBackgroundStyle.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativeSubtitleOverlayView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuView.swift`
- Test: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`

**Interfaces:**
- Produces: public `SubtitleBackgroundStyle: String, CaseIterable, Codable, Sendable` with `.transparent` and `.subtle`, plus `defaultsKey`.
- Consumes: Task 2 `onSelectStyle` callback.

- [ ] **Step 1: Write failing preference and renderer-policy tests**

```swift
func testSubtitleStylesHaveReferenceLabelsAndRealOpacityChanges() {
    XCTAssertEqual(SubtitleBackgroundStyle.transparent.displayName, "Transparent Background")
    XCTAssertEqual(SubtitleBackgroundStyle.subtle.displayName, "Subtle Background")
    XCTAssertEqual(CustomPlayerSubtitlePresentationPolicy.backgroundOpacity(for: .transparent, platform: .tvOS), 0)
    XCTAssertGreaterThan(CustomPlayerSubtitlePresentationPolicy.backgroundOpacity(for: .subtle, platform: .tvOS), 0)
}
```

- [ ] **Step 2: Verify RED**

Run the Task 2 focused-test command. Expected: FAIL because `SubtitleBackgroundStyle` and the policy overload are missing.

- [ ] **Step 3: Implement the shared preference**

```swift
public enum SubtitleBackgroundStyle: String, CaseIterable, Codable, Sendable {
    case transparent
    case subtle

    public static let defaultsKey = "reelfin.subtitle.background-style"

    public var displayName: String {
        switch self {
        case .transparent: "Transparent Background"
        case .subtle: "Subtle Background"
        }
    }
}
```

In `CustomPlayerView`, add:

```swift
@AppStorage(SubtitleBackgroundStyle.defaultsKey)
private var subtitleBackgroundStyle: SubtitleBackgroundStyle = .transparent
```

Use the selected style to return zero background opacity for `.transparent` and the existing platform opacity for `.subtle`. In `NativeSubtitleOverlayView.render(cues:)`, read the raw value from `UserDefaults.standard`, update the label/background style, then render. Style changes must take effect on the next render tick without recreating the player.

- [ ] **Step 4: Run tests and iOS/tvOS builds**

Run the focused test plus both scheme builds. Expected: all pass and iOS remains at 20-point compact subtitles.

- [ ] **Step 5: Commit Task 3**

```bash
git add Shared/Sources/Shared/SubtitleBackgroundStyle.swift \
ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift \
ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativeSubtitleOverlayView.swift \
ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuView.swift \
Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift
git commit -m "feat(player): add functional subtitle background styles"
```

---

### Task 4: Wire Both tvOS Routes And Remote Hierarchy

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuView.swift`
- Modify: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3 model/view/style APIs.
- Produces: identical Audio/Subtitles menu behavior on CustomPlayer and NativePlayer.

- [ ] **Step 1: Write failing state-transition tests**

```swift
func testAVKitMenuNavigationReturnsSubmenuThenDismissesRoot() {
    var state = NativePlayerAVKitMenuState(page: .subtitlesRoot)
    state.perform(.openLanguages)
    XCTAssertEqual(state.page, .subtitleLanguages)
    XCTAssertEqual(state.handleMenu(), .returnedToRoot)
    XCTAssertEqual(state.page, .subtitlesRoot)
    XCTAssertEqual(state.handleMenu(), .dismissed)
}

func testAudioAndSubtitleSelectionDispatchExactlyOnce() {
    var selections: [PlaybackControlSelection] = []
    NativePlayerAVKitMenuDispatch.dispatch(.audio("fr"), to: { selections.append($0) })
    XCTAssertEqual(selections.count, 1)
}
```

- [ ] **Step 2: Verify RED**

Run focused tests. Expected: FAIL because state/dispatch APIs are missing.

- [ ] **Step 3: Wire the view and handlers**

Add a value-state menu state machine to the menu view:

```swift
struct NativePlayerAVKitMenuState: Equatable {
    var page: NativePlayerAVKitMenuPage
    var focusedRow: NativePlayerAVKitMenuRowID?

    mutating func handleMenu() -> NativePlayerAVKitMenuExitResult {
        if NativePlayerAVKitMenuFocusPolicy.parent(of: page) != nil {
            page = .subtitlesRoot
            focusedRow = .subtitleLanguage
            return .returnedToRoot
        }
        return .dismissed
    }
}
```

Pass `subtitleBackgroundStyle`, `onSelectStyle`, and `onDismiss` from both player routes. `onExitCommand` and Left return from submenus before invoking parent dismissal. Audio selection closes the card. Subtitle Language selection returns to the Subtitles root page and updates the active detail. Style selection returns to root and updates the active style detail.

The parent chrome remains mounted and keeps its `focusRequestToken`; closing the root card increments the token and restores the originating action exactly as the current reliable implementation does.

- [ ] **Step 4: Run 64+ focused tests and both builds**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
-project ReelFin.xcodeproj -scheme ReelFin \
-destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
-only-testing:PlaybackEngineTests/NativePlayerChromeLayoutTests \
-only-testing:PlaybackEngineTests/CustomPlayerSupportTests \
-only-testing:PlaybackEngineTests/PlaybackCoordinatorContainerPrefTests \
-only-testing:PlaybackEngineTests/PlaybackStopReportingTests

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build \
-project ReelFin.xcodeproj -scheme ReelFin \
-destination 'generic/platform=iOS Simulator'

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build \
-project ReelFin.xcodeproj -scheme ReelFinTV \
-destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A'
```

Expected: all tests and both builds pass.

- [ ] **Step 5: Commit Task 4**

```bash
git add ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift \
ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerView.swift \
ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerAVKitMenuView.swift \
Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift
git commit -m "feat(tvos): wire AVKit-style menus to both player routes"
```

---

### Task 5: Authenticated UI Proof, Visual Comparison, And Documentation

**Files:**
- Modify: `Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift`
- Modify: `PLANS.md`
- Modify: `OPTIMIZATION_AUDIT.md`

**Interfaces:**
- Consumes: the complete menu implementation.
- Produces: deterministic and live evidence for Audio, Subtitles root, Language, Style, focus restoration, playback continuation, and no errors.

- [ ] **Step 1: Add failing live assertions for all menu pages**

Extend the existing track journey to require these DEBUG tvOS markers and real actions:

```swift
XCTAssertTrue(app.otherElements["native_player_avkit_audio_menu"].waitForExistence(timeout: 8))
XCTAssertTrue(app.otherElements["native_player_avkit_subtitles_root"].waitForExistence(timeout: 8))
XCTAssertTrue(app.otherElements["native_player_avkit_subtitle_languages"].waitForExistence(timeout: 8))
XCTAssertTrue(app.otherElements["native_player_avkit_subtitle_styles"].waitForExistence(timeout: 8))
XCTAssertTrue(app.staticTexts["Transparent Background"].exists)
XCTAssertFalse(app.otherElements["player_error"].exists)
```

Add screenshot attachments named `avkit-audio`, `avkit-subtitles-root`, `avkit-language`, and `avkit-style`.

- [ ] **Step 2: Run the live journey and verify RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
-project ReelFin.xcodeproj -scheme ReelFinTV \
-destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A' \
-only-testing:ReelFinTVUITests/TVPlayerLiveUserJourneyTests/testAudioSubtitlesVideoInfoDetailsAndPausedContinue
```

Expected: FAIL before markers/navigation are added or before pages match the hierarchy.

- [ ] **Step 3: Add markers, finish navigation, and compare captures**

Gate markers behind the existing exact `DEBUG && os(tvOS)` live-automation policy. Navigate with `XCUIRemote`, assert actual focus before Select, change one audio track, one subtitle language, and both subtitle styles, then verify playback resumes and advances after every selection.

Inspect all four captures against the supplied references. Reject the result if any card uses opaque black fill, generic list rows, nested glass that hides text, full-white focus capsules, missing checkmarks, missing detail labels, or missing chevrons.

- [ ] **Step 4: Run final validation**

Run:

```bash
xcodegen generate
git diff --check

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
-project ReelFin.xcodeproj -scheme ReelFinTV \
-destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A'
```

Expected: local tests plus all opt-in Star City journeys pass with zero player errors. Re-run the ten-cycle Continue/Restart journey if any shared focus or menu lifecycle code changed during the live-fix loop.

- [ ] **Step 5: Update docs and commit**

Record exact test counts, build results, live durations, capture paths, visual comparison outcome, and the simulator-only audio/HDR limitations in `PLANS.md` and `OPTIMIZATION_AUDIT.md`.

```bash
git add Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift PLANS.md OPTIMIZATION_AUDIT.md
git commit -m "test(tvos): prove AVKit-faithful custom player menus"
```
