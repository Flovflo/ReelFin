# Native iPad Build 17 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a locally validated, native universal ReelFin iOS archive for candidate `0.1.2 (17)`, while preserving the iPhone experience and the effective tvOS build.

**Architecture:** `project.yml` remains the sole project source. The existing root view gains no second navigation tree: regular iPad windows use its split shell and compact windows retain tabs. A pure orientation policy keeps existing iPhone rotation behaviour but makes iPad window-aware and non-forcing.

**Tech Stack:** Swift 6, SwiftUI/UIKit public APIs, XCTest/XCUITest, XcodeGen, Xcode beta 26.5 simulator runtimes; Xcode 26.6 only for a distribution archive after its licence is already accepted.

## Global Constraints

- iOS target only: `TARGETED_DEVICE_FAMILY = "1,2"`; tvOS remains family `3`, with its effective version/build unchanged.
- Candidate iOS build is `17` only after App Store Connect (ASC) says it is unused; query ASC again immediately before archive and hard-stop on a collision.
- Do not add `UIRequiresFullScreen`; iPad supports all orientations and never forces scene geometry. Keep iPhone portrait browsing, landscape player, and portrait restoration.
- Use Swift 6 and public Apple playback/UI APIs; no secret, account, server, or personal media belongs in sources, logs, captures, or commits.
- No upload, tester distribution, App Store metadata change, or tvOS archive occurs in this plan. Security remediation and its verification are mandatory prerequisites for any later upload.
- Archive locally only with `/Users/flo/Applications/Xcode-26.6.app` after `xcodebuild -checkFirstLaunchStatus` succeeds; never accept a licence on another person's behalf. Use beta Xcode 26.5 for simulator tests.

---

## File Map

- `project.yml`: iOS-only candidate build, universal family, iPad orientations; regenerate generated files from it.
- `scripts/preflight_testflight_release.sh`: release contract and archive-only/security hard stops.
- `ReelFinUI/Sources/ReelFinUI/PlayerOrientationPolicy.swift`, `OrientationManager.swift`, `RootLayoutPlatformPolicy.swift`, `ReelFinRootView.swift`, `ReelFinApp/App/AppDelegate.swift`: adaptive iPad behavior.
- `Tests/PlaybackEngineTests/PlayerOrientationLockTests.swift`, `RootDesktopLayoutPolicyTests.swift`, `Tests/ReelFinUITests/IPadAdaptiveUITests.swift`, `ReelFinUITests.swift`: unit/UI/capture proof.
- `Docs/Media/AppStoreReady/13-inch/screenshots/*.png` and release docs: fictional 13-inch assets and accurate support/release copy.

### Task 1: Make preflight reject the current iPhone-only product (RED)

**Files:**
- Modify: `scripts/preflight_testflight_release.sh`
- Test: `scripts/preflight_testflight_release.sh`

**Produces:** a deterministic local gate for an iOS-only build 17, family `1,2`, four iPad orientations, family-3 tvOS, and four 13-inch screenshots.

- [ ] Add assertions that parse the `ReelFinApp` section (not the global build value): require `CURRENT_PROJECT_VERSION: 17` below `ReelFinApp.settings.base`, `TARGETED_DEVICE_FAMILY: "1,2"`, four `UISupportedInterfaceOrientations~ipad` values, and `ReelFinTVApp` family `3` with its existing effective build.

```zsh
require_plist_array_member() {
  local path="$1" key="$2" expected="$3" label="$4" values
  values="$(/usr/libexec/PlistBuddy -c "Print :${key}" "$ROOT_DIR/$path" 2>/dev/null || true)"
  if /usr/bin/grep -Fq -- "$expected" <<<"$values"; then pass "$label"; else fail "$label"; fi
}
require_contains "project.yml" 'TARGETED_DEVICE_FAMILY: "1,2"' "iOS app is configured for iPhone and iPad"
reject_contains "project.yml" 'UIRequiresFullScreen' "iPad multitasking is not disabled"
require_plist_array_member "$APP_INFO_PLIST" "UISupportedInterfaceOrientations~ipad" \
  "UIInterfaceOrientationPortraitUpsideDown" "iPad supports all orientations"
```

- [ ] Require `Docs/Media/AppStoreReady/13-inch/screenshots/{01-home,02-library,03-detail,04-settings}.png` at `2064x2752`, plus documentation wording `iPhone, iPad, and Apple TV`.
- [ ] Run RED:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer scripts/preflight_testflight_release.sh
```

Expected: it fails specifically for family, iOS-target build 17, iPad orientations, captures, and docs; retain no permissive iPhone-only assertion.

- [ ] Mutation proof: temporarily remove the `1,2` assertion and confirm its named failure disappears, then restore it. Commit the contract: `git commit -am "test(release): require native iPad build"` (stage only this script).

### Task 2: Declare a universal, iOS-only candidate build (GREEN)

**Files:**
- Modify: `project.yml`
- Regenerate: `ReelFin.xcodeproj`, `ReelFinApp/App/Info.plist`

**Consumes:** Task 1. **Produces:** iOS `0.1.2 (17)`, `[1,2]`, four iPad orientations; unchanged effective tvOS build/family.

- [ ] Before mutation, query ASC build history for app `6762079357`, bundle `com.reelfin.app`, iOS platform. Record only whether `17` is free; stop on occupied/unknown result. Do not print credentials or upload.
- [ ] In `ReelFinApp.settings.base`, override `CURRENT_PROJECT_VERSION: 17` and set `TARGETED_DEVICE_FAMILY: "1,2"`; leave the top-level/current tvOS build setting and `ReelFinTVApp` unchanged. Add the iPad orientation array to `ReelFinApp.info.properties`; do not add `UIRequiresFullScreen`.
- [ ] Regenerate and inspect exact effective settings:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project ReelFin.xcodeproj -scheme ReelFin -configuration Release -destination 'generic/platform=iOS' -showBuildSettings | rg 'CURRENT_PROJECT_VERSION|TARGETED_DEVICE_FAMILY'
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project ReelFin.xcodeproj -scheme ReelFinTV -configuration Release -destination 'generic/platform=tvOS' -showBuildSettings | rg 'CURRENT_PROJECT_VERSION|TARGETED_DEVICE_FAMILY'
```

Expected: iOS `17`/`1,2`; tvOS is its pre-change build/`3`. Run Task 1 GREEN for config checks, `git diff --check`, and commit only source/generated project files.

### Task 3: Make orientation idiom-aware with unit-test-first development

**Files:**
- Create: `ReelFinUI/Sources/ReelFinUI/PlayerOrientationPolicy.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/OrientationManager.swift`, `ReelFinApp/App/AppDelegate.swift`, `Tests/PlaybackEngineTests/PlayerOrientationLockTests.swift`

**Produces:** `PlayerOrientationPolicy.supportedOrientations(idiom:context:) -> UIInterfaceOrientationMask` and `requestedGeometryOrientation(idiom:context:) -> UIInterfaceOrientationMask?`.

- [ ] RED: add exact matrix tests: `.phone/.browsing == .portrait`; `.phone/.player == .landscape` and `.landscapeRight`; `.pad` in both contexts is `.all` with nil geometry request. Add injected idiom/callback tests proving iPad player appearance and dismissal make zero geometry requests.
- [ ] Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/PlayerOrientationLockTests
```

Expected RED because policy/API is absent.
- [ ] GREEN: implement the pure policy with `UIUserInterfaceIdiom`; have `OrientationManager` retain a browsing/player context and invoke geometry only for a non-nil policy result. `AppDelegate` passes `window?.traitCollection.userInterfaceIdiom`. No force request on iPad.
- [ ] Mutation: return `.landscape` or `.landscapeRight` for iPad and verify the focused test fails; restore, rerun GREEN, commit the four files.

### Task 4: Make the existing root shell native-adaptive

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/RootLayoutPlatformPolicy.swift`, `ReelFinUI/Sources/ReelFinUI/ReelFinRootView.swift`, `Tests/PlaybackEngineTests/RootDesktopLayoutPolicyTests.swift`

**Produces:** `shouldUseSplitLayout(isRegularHorizontalSizeClass:isPadIdiom:isMacCatalyst:) -> Bool` and identifiers `root_split_layout`, `root_tab_layout`, `root_sidebar`, `root_sidebar_home`, `root_sidebar_search`, `root_sidebar_settings`.

- [ ] RED: unit-test regular iPad => true even in screenshot mode, compact iPad => false, iPhone => false, Catalyst => false. Run targeted `RootDesktopLayoutPolicyTests` on iPhone 17/iOS 26.5 and observe the former screenshot-coupled interface fail.
- [ ] GREEN: remove screenshot-mode from the split decision; return `isPadIdiom && isRegularHorizontalSizeClass && !isMacCatalyst`. Attach the identifiers to the existing split/tab/sidebar/destinations only—no routing model or parallel iPad UI.
- [ ] Mutation: force false on a regular iPad, observe the unit/UI native-shell assertion fail, restore and commit.

### Task 5: Prove adaptive behavior on both iPad extremes before visual fixes

**Files:**
- Create: `Tests/ReelFinUITests/IPadAdaptiveUITests.swift`
- Modify only upon a demonstrated failure: `ReelFinRootView.swift`, `LoginView.swift`, `HomeView.swift`, `LibraryView.swift`, `DetailView.swift`, or focused helpers.

- [ ] RED: create deterministic mock-mode tests (no real Jellyfin): Pro 13 regular window exposes split/sidebar and not tabs; Home/Search/Settings are hittable; first home/library cards and detail play control have non-zero frames within the window and right of the sidebar; logged-out controls remain hittable after portrait/landscape; a mock player remains visible while the window rotates.
- [ ] Run on both destinations, bounded waits only:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' -only-testing:ReelFinUITests/IPadAdaptiveUITests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro),OS=26.5' -only-testing:ReelFinUITests/IPadAdaptiveUITests
```

- [ ] GREEN: fix each observed clipping/containment defect with size classes, safe areas, adaptive grids or bounded widths; never `UIScreen.main.bounds`, fixed device checks, sleeps, iPad-only routes, or tvOS edits. Mutation-force compact shell on regular iPad and confirm the native-shell test fails. Commit.

### Task 6: Capture the App Store iPad set and align release docs

**Files:**
- Modify: `Tests/ReelFinUITests/ReelFinUITests.swift`, `README.md`, `Docs/README.md`, `Docs/AppStore-Submission.md`, `Docs/TestFlight-Launch-Checklist.md`, `Docs/privacy-policy.html`, `Docs/terms-of-service.html`
- Create: `Docs/Media/AppStoreReady/13-inch/screenshots/01-home.png`, `02-library.png`, `03-detail.png`, `04-settings.png`

- [ ] RED/GREEN: on iPad Pro 13/iOS 26.5, make the screenshot test assert portrait plus `root_split_layout` before exporting deterministic fictional Home/Library/Detail/Settings into the exact directory. Use `sips` to require each `2064x2752`; visually reject phone compatibility UI, clipping, spinners/errors, test chrome, or real account/media/server data.
- [ ] Update active documentation to `iPhone, iPad, and Apple TV`, `0.1.2 (17)`, iOS/tvOS 26.5 commands, iPad resize/orientation testing, and the three screenshot directories. Preserve privacy data-practice claims. Run preflight GREEN and stale-claim scan:

```bash
rg -n 'iPhone and Apple TV|AppStore/Screenshots|OS=26\.2|OS=26\.3\.1' README.md Docs scripts project.yml
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer scripts/preflight_testflight_release.sh
```

- [ ] Mutation-disable split layout; screenshot test must fail before accepting images. Restore, regenerate captures, commit docs/assets/tests.

### Task 7: Complete matrix, archive locally, and hand off securely

**Files:** no tracked source changes; local-only `.artifacts/ipad-build17/`.

- [ ] Regenerate, then build/test: full iPhone 17/iOS 26.5; focused/full iPad Pro 13 and iPad mini/iOS 26.5; full ReelFinTV Apple TV 4K (3rd generation)/tvOS 26.5. Persist `.xcresult` evidence locally; reproduce each failure with one focused command and a new RED/GREEN fix—never add skips or sleeps.
- [ ] Before archive, repeat ASC iOS build-17 query and hard-stop if it is occupied. Verify branch/revision/clean intended diff and use only Xcode 26.6 if its licence check succeeds:

```bash
DEVELOPER_DIR=/Users/flo/Applications/Xcode-26.6.app/Contents/Developer xcodebuild -checkFirstLaunchStatus
DEVELOPER_DIR=/Users/flo/Applications/Xcode-26.6.app/Contents/Developer xcodebuild archive -project ReelFin.xcodeproj -scheme ReelFin -configuration Release -destination 'generic/platform=iOS' -archivePath "$PWD/.artifacts/ipad-build17/ReelFin-0.1.2-17.xcarchive"
```

- [ ] Inspect archive app plist and signing. Hard-stop unless identifier is `com.reelfin.app`, version `0.1.2`, build `17`, device family `[1,2]`, and all four iPad orientations are compiled; ensure tvOS was not archived.
- [ ] Handoff only: report test matrix, two ASC results, Xcode licence/archive status, plist/signing evidence, and any blocker to the security-gated release owner. Do not call `asc publish`, export an IPA, notify testers, or submit/upload anything.

## Definition of Done

- Universal iOS archive proof: `[1,2]`, all iPad orientations, no full-screen opt-out, iOS build 17, expected signing.
- iPhone/iPad/tvOS matrix is green on 26.5 with the native Pro/mini UI assertions and four reviewed 13-inch fictional captures.
- tvOS effective build and binary scope remain untouched; ASC build collision and Xcode 26.6 licence gates are factual hard stops.
- Upload remains explicitly blocked until independent security remediation/verification is complete.
