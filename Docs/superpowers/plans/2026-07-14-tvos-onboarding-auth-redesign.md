# tvOS Onboarding and Authentication Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ReelFin’s crowded tvOS onboarding with a cinematic, remote-first four-page experience and make authentication focus/back navigation deterministic without changing iOS.

**Architecture:** Pure value policies own onboarding page movement and authentication focus/back routing, which makes remote behavior unit-testable. Platform-specific SwiftUI views render one active authentic ReelFin screen in a bounded 16:9 aspect-fit frame, large 10-foot copy, and a compact native Liquid Glass action rail; existing login view models and Jellyfin calls remain unchanged.

**Tech Stack:** Swift 5, SwiftUI on tvOS 26+, XCTest/XCUITest, XcodeGen, Apple Liquid Glass APIs.

## Global Constraints

- The redesigned surface is tvOS 26 and later; iOS behavior and layout must remain unchanged.
- Keep the existing four-page onboarding version gate and do not force already-onboarded users through it again.
- Render only the active 1920×1080 scene; remove the fake television, stand, and all marketing callouts.
- Essential content stays at least 80 pt from horizontal edges and 60 pt from vertical edges at 1920×1080.
- Onboarding title is 60 pt bold, support copy is 30 pt medium, and button labels are at least 29 pt semibold.
- Liquid Glass is used for interactive controls and compact grouping only, never as a giant noninteractive content panel.
- Default focus must use focus APIs and must not depend on fixed sleeps.
- Menu/back uses the same reducer as visible Back controls and cancels Quick Connect when leaving that route.
- Reduce Motion disables continuous drift, blur, spring bounce, and scale-based focus movement.
- No simulator erase, app uninstall, physical Apple TV action, third-party media engine, or private API.
- Tests use mock launch arguments and must not require a live Jellyfin server.

---

## File Structure

- `ReelFinUI/Sources/ReelFinUI/TV/TVAuthNavigationPolicy.swift`: pure onboarding deck and login focus/back policies.
- `ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingContent.swift`: four-page content descriptors and aspect-fit layout policy.
- `ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingView.swift`: onboarding orchestration, focus, Menu, copy, progress, and action rail.
- `ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingHeroView.swift`: one complete 16:9 product screen, static ambient backdrop, edge highlight, and no scene movement.
- `ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingShowcaseView.swift`: delete; its fake television and callout components have no remaining responsibility.
- `ReelFinUI/Sources/ReelFinUI/TV/TVLoginView.swift`: route transitions, Quick Connect origin, deterministic focus, and Menu/back behavior.
- `ReelFinUI/Sources/ReelFinUI/TV/TVLoginModels.swift`: route-specific focus cases and safe layout metrics.
- `ReelFinUI/Sources/ReelFinUI/TV/TVLoginStageViews.swift`: stable identifiers and accessible stage controls.
- `ReelFinUI/Sources/ReelFinUI/TV/TVLoginVisualSystem.swift`: 10-foot type, native glass controls, and Reduce Motion-aware focus styling.
- `ReelFinUI/Sources/ReelFinUI/TV/TVAuthFlowView.swift`: Reduce Motion-aware onboarding-to-login transition.
- `Tests/ReelFinTVTests/TVAuthNavigationPolicyTests.swift`: deterministic unit coverage.
- `Tests/ReelFinTVUITests/TVAuthFlowUITests.swift`: mock remote journey coverage.
- `project.yml`: make `ReelFinTVTests` depend on `ReelFinUITV`.
- `PLANS.md`, `OPTIMIZATION_AUDIT.md`: record focus/auth/rendering changes and validation.

---

### Task 1: Deterministic onboarding and authentication policies

**Files:**
- Create: `Tests/ReelFinTVTests/TVAuthNavigationPolicyTests.swift`
- Create: `ReelFinUI/Sources/ReelFinUI/TV/TVAuthNavigationPolicy.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/TV/TVLoginModels.swift`
- Modify: `project.yml`

**Interfaces:**
- Produces: `TVOnboardingDeckState.init(initialIndex:count:)`, `advance() -> TVOnboardingAdvanceResult`, and `retreat() -> Bool`.
- Produces: `TVLoginNavigationPolicy.preferredFocus(for:) -> TVLoginFocus?` and `backDestination(from:quickConnectOrigin:) -> TVLoginPhase?`.
- Produces route-specific `TVLoginFocus` cases consumed by Tasks 2 and 3.

- [ ] **Step 1: Add the UI module dependency and write failing policy tests**

Add `ReelFinUITV` under `ReelFinTVTests.dependencies` in `project.yml`, then create tests equivalent to:

```swift
import XCTest
@testable import ReelFinUI

final class TVAuthNavigationPolicyTests: XCTestCase {
    func testDeckClampsInitialPageAndCompletesOnlyAtLastPage() {
        var deck = TVOnboardingDeckState(initialIndex: 99, count: 4)
        XCTAssertEqual(deck.index, 3)
        XCTAssertEqual(deck.advance(), .completed)
    }

    func testDeckAdvancesAndRetreatsWithoutCrossingBounds() {
        var deck = TVOnboardingDeckState(initialIndex: 0, count: 4)
        XCTAssertEqual(deck.advance(), .advanced)
        XCTAssertEqual(deck.index, 1)
        XCTAssertTrue(deck.retreat())
        XCTAssertEqual(deck.index, 0)
        XCTAssertFalse(deck.retreat())
    }

    func testEveryInteractiveLoginPhaseHasRouteSpecificPreferredFocus() {
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .landing), .landingQuickConnect)
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .server), .serverAddress)
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .credentials), .credentialsUsername)
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .quickConnect), .quickConnectUsePassword)
        XCTAssertNil(TVLoginNavigationPolicy.preferredFocus(for: .submitting))
        XCTAssertNil(TVLoginNavigationPolicy.preferredFocus(for: .success))
    }

    func testBackDestinationsRespectQuickConnectOrigin() {
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .server, quickConnectOrigin: .landing), .landing)
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .credentials, quickConnectOrigin: .landing), .server)
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .quickConnect, quickConnectOrigin: .landing), .landing)
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .quickConnect, quickConnectOrigin: .server), .server)
        XCTAssertNil(TVLoginNavigationPolicy.backDestination(from: .landing, quickConnectOrigin: .landing))
    }
}
```

- [ ] **Step 2: Generate the project and verify RED**

Run:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A' \
  -only-testing:ReelFinTVTests/TVAuthNavigationPolicyTests
```

Expected: compilation fails because the two policy types and route-specific focus cases do not exist.

- [ ] **Step 3: Implement the minimal policies**

Create the following public-to-module shapes:

```swift
#if os(tvOS)
enum TVOnboardingAdvanceResult: Equatable { case advanced, completed }

struct TVOnboardingDeckState: Equatable {
    private(set) var index: Int
    let count: Int

    init(initialIndex: Int?, count: Int) {
        self.count = max(count, 1)
        index = min(max(initialIndex ?? 0, 0), self.count - 1)
    }

    var isFirstPage: Bool { index == 0 }
    var isLastPage: Bool { index == count - 1 }

    mutating func advance() -> TVOnboardingAdvanceResult {
        guard !isLastPage else { return .completed }
        index += 1
        return .advanced
    }

    mutating func retreat() -> Bool {
        guard !isFirstPage else { return false }
        index -= 1
        return true
    }
}

enum TVLoginNavigationPolicy {
    static func preferredFocus(for phase: TVLoginPhase) -> TVLoginFocus? {
        switch phase {
        case .landing: .landingQuickConnect
        case .server: .serverAddress
        case .credentials: .credentialsUsername
        case .quickConnect: .quickConnectUsePassword
        case .submitting, .success: nil
        }
    }

    static func backDestination(
        from phase: TVLoginPhase,
        quickConnectOrigin: TVLoginPhase
    ) -> TVLoginPhase? {
        switch phase {
        case .landing, .submitting, .success:
            nil
        case .server:
            .landing
        case .credentials:
            .server
        case .quickConnect:
            switch quickConnectOrigin {
            case .landing, .server, .credentials:
                quickConnectOrigin
            case .quickConnect, .submitting, .success:
                .landing
            }
        }
    }
}
#endif
```

Make `TVLoginPhase` conform to `Equatable`. Replace generic focus cases with:

```swift
enum TVLoginFocus: Hashable {
    // Transitional compatibility for existing stage bindings. Task 3 removes these
    // after every consumer has moved to a route-specific case.
    case primary
    case secondary
    case tertiary
    case textA
    case textB
    case landingQuickConnect
    case landingPassword
    case landingChooseServer
    case serverAddress
    case serverBack
    case serverPrimary
    case serverAlternate
    case credentialsUsername
    case credentialsPassword
    case credentialsBack
    case credentialsSubmit
    case credentialsQuickConnect
    case quickConnectUsePassword
}
```

Task 1 must not migrate `TVLoginView` or `TVLoginStageViews`; keeping the five compatibility cases is required so the module compiles between Tasks 1 and 3. Task 3 removes all five after migrating every consumer.

- [ ] **Step 4: Verify GREEN and the tvOS unit baseline**

Run the targeted command from Step 2, then:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A' \
  -only-testing:ReelFinTVTests
```

Expected: all policy tests and the existing notification tests pass.

- [ ] **Step 5: Restore normalized generated scheme metadata and commit**

Do not commit XcodeGen-only churn that changes `BuildableName` from `ReelFin.app`. Commit `project.yml`, the policy, model, and tests:

```bash
git add project.yml ReelFinUI/Sources/ReelFinUI/TV/TVAuthNavigationPolicy.swift \
  ReelFinUI/Sources/ReelFinUI/TV/TVLoginModels.swift \
  Tests/ReelFinTVTests/TVAuthNavigationPolicyTests.swift
git commit -m "test(tvOS): define auth navigation policy"
```

---

### Task 2: Cinematic four-page onboarding

**Files:**
- Create: `Tests/ReelFinTVUITests/TVAuthFlowUITests.swift`
- Create: `ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingHeroView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingContent.swift`
- Delete: `ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingShowcaseView.swift`

**Interfaces:**
- Consumes: `TVOnboardingDeckState` from Task 1.
- Produces stable UI identifiers `tv_onboarding_screen`, `tv_onboarding_title`, `tv_onboarding_progress`, `tv_onboarding_back`, and `tv_onboarding_primary_cta`.
- Produces `TVOnboardingHeroView(item:)`, which renders only one item.

- [ ] **Step 1: Write failing mock UI tests**

Create a UI test class that launches with:

```swift
app.launchArguments = [
    "-reelfin-mock-mode", "-reelfin-ui-logged-out",
    "-reelfin-tv-auth-screen", "onboarding",
    "-reelfin-tv-onboarding-page", "0"
]
```

Add separate tests that assert:

```swift
XCTAssertTrue(app.otherElements["tv_onboarding_screen"].waitForExistence(timeout: 8))
XCTAssertTrue(app.buttons["tv_onboarding_primary_cta"].hasFocus)
XCTAssertFalse(app.buttons["tv_onboarding_back"].exists)

XCUIRemote.shared.press(.select)
XCTAssertTrue(app.staticTexts["tv_onboarding_title"].waitForExistence(timeout: 3))
XCTAssertTrue(app.buttons["tv_onboarding_back"].exists)
XCUIRemote.shared.press(.menu)
XCTAssertFalse(app.buttons["tv_onboarding_back"].exists)
XCTAssertEqual(app.state, .runningForeground)
```

Include a geometry assertion that each action frame lies inside `app.windows.firstMatch.frame.insetBy(dx: 80, dy: 60)`.

- [ ] **Step 2: Verify RED**

Run:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A' \
  -only-testing:ReelFinTVUITests/TVAuthFlowUITests
```

Expected: the first test fails because the current screen has no stable screen identifier/default-focus contract, and later assertions expose the transparent Back control/Menu behavior.

- [x] **Step 3: Replace the fake television with one bounded authentic product screen**

`TVOnboardingHeroView` must:

```swift
TVOnboardingScreenshotImage(name: item.screenshotName)
    .aspectRatio(16.0 / 9.0, contentMode: .fit)
    .frame(width: metrics.heroFrame.width, height: metrics.heroFrame.height)
    .clipShape(.rect(cornerRadius: 38))
.accessibilityHidden(true)
```

Render only `items[deck.index]`. Delete the fake bezel, stand, all badges/notes/minis, inactive page stacking, zoom, drift, crop, blur, and shadow hierarchy. Use four distinct screenshots captured from the current tvOS build: Home, Library, Detail, and the real Star City Skip Intro player state.

- [ ] **Step 4: Build the safe copy and compact action rail**

Rebuild `TVOnboardingView` around `TVOnboardingDeckState` with 80 pt horizontal and 60 pt vertical content insets. Use 60 pt title, 30 pt subtitle, one compact accessible progress indicator, and one prominent CTA. Insert the Back button only when `!deck.isFirstPage`.

Use `.defaultFocus($focusedControl, .primary, priority: .userInitiated)` and synchronous focus assignment; remove `Task.sleep`. Add `.onExitCommand(perform: retreat)` and consume Menu on page 1. On the final page, the CTA title is `Connect My Server`.

- [ ] **Step 5: Verify GREEN, capture all four pages, and inspect visually**

Run the UI test command from Step 2. Then launch each page with the existing debug argument and capture screenshots under `.artifacts/design-audit/tvos-onboarding-redesign/` without erasing simulator state.

Acceptance from the captures:

- no fake television or stand;
- no crop, zoom, pan, or continuous motion;
- four distinct real ReelFin product screens remain fully visible at 16:9;
- no overlap between artwork, copy, and action rail;
- no text below 29 pt except quiet progress/brand metadata;
- focused CTA clearly visible from the full 1920×1080 image;
- all actions inside the safe rectangle.

- [ ] **Step 6: Commit**

```bash
git add ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingView.swift \
  ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingHeroView.swift \
  ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingContent.swift \
  ReelFinUI/Sources/ReelFinUI/TV/TVOnboardingShowcaseView.swift \
  Tests/ReelFinTVUITests/TVAuthFlowUITests.swift
git commit -m "feat(tvOS): rebuild onboarding as cinematic deck"
```

---

### Task 3: Remote-first authentication focus and Menu navigation

**Files:**
- Modify: `Tests/ReelFinTVUITests/TVAuthFlowUITests.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/TV/TVLoginView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/TV/TVLoginStageViews.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/TV/TVLoginVisualSystem.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/TV/TVLoginModels.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/TV/TVAuthFlowView.swift`

**Interfaces:**
- Consumes: `TVLoginNavigationPolicy` and route-specific focus cases from Task 1.
- Produces stable identifiers for landing, server, credentials, Quick Connect, success, every field, and every actionable button.
- Keeps `LoginViewModel` and `QuickConnectViewModel` API behavior unchanged.

- [ ] **Step 1: Add failing route/focus UI tests**

Use direct debug phases to assert default focus:

```swift
launchLogin(phase: "landing")
XCTAssertTrue(app.buttons["tv_login_quick_connect"].hasFocus)

launchLogin(phase: "server")
XCTAssertTrue(app.textFields["tv_login_server_field"].hasFocus)

launchLogin(phase: "credentials")
XCTAssertTrue(app.textFields["tv_login_username_field"].hasFocus)
```

Add journeys proving Menu maps server → landing and credentials → server, and that entering then leaving Quick Connect exposes the originating route without exiting the app.

- [ ] **Step 2: Verify RED**

Run the targeted tvOS UI test class. Expected: queries fail because identifiers do not exist and current Menu behavior is not implemented.

- [ ] **Step 3: Route every control to a unique focus case**

Replace `.primary/.secondary/.tertiary/.textA/.textB` bindings with explicit cases such as:

```swift
case landingQuickConnect, landingPassword, landingChooseServer
case serverAddress, serverBack, serverPrimary, serverAlternate
case credentialsUsername, credentialsPassword, credentialsBack, credentialsSubmit, credentialsQuickConnect
case quickConnectUsePassword
```

On each phase change, set the policy’s preferred focus and apply `.defaultFocus` at the stage scope. When a credentials submission fails, explicitly prefer `credentialsPassword`.

- [ ] **Step 4: Add one central back reducer**

Track `quickConnectOrigin` before starting Quick Connect. Add:

```swift
private func navigateBack() {
    guard let destination = TVLoginNavigationPolicy.backDestination(
        from: phase,
        quickConnectOrigin: quickConnectOrigin
    ) else { return }

    if phase == .quickConnect { quickConnectVM.cancel() }
    go(destination)
}
```

Visible Back actions and `.onExitCommand` call `navigateBack`. Route changes must assign default focus without sleeps.

- [ ] **Step 5: Refine type, glass, accessibility, and Reduce Motion**

- Stage title: 52–56 pt bold; support text: 29 pt medium.
- Button labels: 29 pt semibold; controls at least 82 pt high.
- Focus scale: ReelFin’s 1.06 token when Reduce Motion is off; 1.0 with contrast-only feedback when on.
- Keep native `.glassProminent`/`.glass` styles on tvOS 26.
- Add identifiers and accessibility labels to every field and action.
- Make `TVAuthFlowView` use a short crossfade without scale/bounce, and keep login stage/success transitions non-bouncy.

- [ ] **Step 6: Verify GREEN and inspect every login stage**

Run the targeted UI tests and the Task 1 unit tests. Capture landing, server, credentials, Quick Connect, submitting, and success under `.artifacts/design-audit/tvos-login-redesign/`. Confirm title wrapping, focus visibility, control overlap, and safe-area compliance.

- [ ] **Step 7: Commit**

```bash
git add ReelFinUI/Sources/ReelFinUI/TV/TVLoginView.swift \
  ReelFinUI/Sources/ReelFinUI/TV/TVLoginStageViews.swift \
  ReelFinUI/Sources/ReelFinUI/TV/TVLoginVisualSystem.swift \
  ReelFinUI/Sources/ReelFinUI/TV/TVLoginModels.swift \
  ReelFinUI/Sources/ReelFinUI/TV/TVAuthFlowView.swift \
  Tests/ReelFinTVUITests/TVAuthFlowUITests.swift
git commit -m "fix(tvOS): make auth focus and back deterministic"
```

---

### Task 4: Documentation, build gates, and simulator acceptance

**Files:**
- Modify: `PLANS.md`
- Modify: `OPTIMIZATION_AUDIT.md`
- Modify only if generated source changes require it: `ReelFin.xcodeproj`

**Interfaces:**
- Consumes the completed onboarding/auth surface and tests from Tasks 1–3.
- Produces a reproducible evidence record and no new runtime behavior.

- [ ] **Step 1: Record the implementation and evidence**

Append concise dated entries covering:

- single active onboarding scene instead of four blurred scenes;
- no sleep-based focus handoff;
- deterministic Menu/back policy and Quick Connect cancellation;
- Reduce Motion behavior;
- exact unit/UI/build commands and screenshot artifact directories.

- [ ] **Step 2: Regenerate and preserve the unified product naming**

Run `xcodegen generate`. Confirm generated targets still use `PRODUCT_NAME = ReelFin`; restore the repository’s normalized scheme `BuildableName = ReelFin.app` metadata before committing if XcodeGen rewrites only that metadata.

- [ ] **Step 3: Run fresh tvOS verification**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A'

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build \
  -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A'
```

Expected: zero failures and exit code 0. The opt-in live Star City tests may skip when their alias environment is absent; the mock auth tests must execute and pass.

- [ ] **Step 4: Run fresh iOS isolation verification**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06'
```

Expected: exit code 0 with no iOS onboarding source change.

- [ ] **Step 5: Relaunch the preserved tvOS simulator normally**

Terminate the mock launch and launch `com.reelfin.app` with no debug arguments. Do not erase or uninstall. Confirm it remains foreground and the existing data container still exists.

- [ ] **Step 6: Commit documentation/evidence metadata**

```bash
git add PLANS.md OPTIMIZATION_AUDIT.md ReelFin.xcodeproj
git commit -m "docs(tvOS): record onboarding validation"
```

Do not add `.artifacts/` screenshots or logs to Git.

---

## Self-Review Results

- **Spec coverage:** Every visual, focus, Menu/back, Quick Connect, Reduce Motion, accessibility, safe-area, simulator-preservation, and cross-platform build requirement maps to a task.
- **Placeholder scan:** The plan contains no TBD/TODO/future implementation placeholders. Policy switches and focus cases are fully enumerated.
- **Type consistency:** `TVOnboardingDeckState`, `TVOnboardingAdvanceResult`, `TVLoginNavigationPolicy`, `TVLoginPhase`, and route-specific `TVLoginFocus` names are consistent across tasks.
- **Scope:** Broader authenticated tvOS audit findings remain outside this atomic redesign, as required by the approved design spec.
