# Native iPad Build 17 Design

## Objective

Prepare ReelFin's iOS application as a genuine universal iPhone+iPad binary, using candidate version `0.1.2 (17)` only if App Store Connect still reports that iOS build number as unused. The change must preserve the existing iPhone experience, leave the tvOS product and effective tvOS build unchanged, and end with a signed archive plus local validation evidence. TestFlight upload and distribution remain outside this design until the security remediation workstream is complete.

## Current Evidence

- `project.yml` is the XcodeGen source of truth. It currently sets the iOS family to `1`, so the product is iPhone-only even though `ReelFinRootView` already contains an iPad `NavigationSplitView` branch.
- `scripts/preflight_testflight_release.sh` currently enforces family `1` and rejects family `1,2`.
- `ReelFinApp/App/Info.plist` contains only the iPhone orientation declaration.
- `RootLayoutPlatformPolicy.shouldUseSplitLayout(...)` disables the iPad split shell in screenshot mode.
- `OrientationManager` owns a global portrait/landscape mask and always requests geometry changes. That is suitable for the current iPhone convention but not for freely resizable iPad windows.
- The local beta Xcode provides the iOS/tvOS 26.5 simulator runtimes and a Swift 6 toolchain. Distribution must prefer `/Users/flo/Applications/Xcode-26.6.app`; that installation is currently unusable until its license is accepted by a person with the required local authority. The implementation must detect and report this condition, never claim to accept the license itself.

## Chosen Design

### Universal target without a second tablet product

The existing `ReelFinApp` target becomes family `1,2`; it remains on `iphoneos iphonesimulator` because iPadOS uses the iOS SDK. `UIRequiresFullScreen` is not introduced. `project.yml` declares all four iPad orientations, and the archived application's compiled plist—not simulator launch alone—is the final proof of native iPad eligibility.

Candidate build `17` is scoped to `ReelFinApp.settings.base.CURRENT_PROJECT_VERSION`. The existing global build value and the effective `ReelFinTVApp` build remain unchanged. This avoids turning an iPad-only release slice into an unrequested tvOS binary update. Build `17` may be written only after a fresh App Store Connect query proves it unused; the same query is repeated immediately before archive and must hard-stop on a collision.

### Adaptive navigation

A regular-width iPad uses the existing `NavigationSplitView` shell and sidebar. An iPhone or compact-width iPad uses the existing tab shell. The decision depends on horizontal size class, iPad idiom, and Catalyst state—not screenshot mode—so deterministic storefront captures exercise the real tablet hierarchy.

Stable accessibility identifiers expose the selected shell and sidebar destinations to XCUITest. No separate iPad navigation tree, new routing model, or hard-coded device-size branch is introduced.

### Idiom-aware orientation policy

A small pure policy maps `(UIUserInterfaceIdiom, PlayerOrientationContext)` to supported orientations and an optional geometry request:

| Idiom | Context | Supported | Requested geometry |
|---|---|---|---|
| iPhone | browsing | portrait | portrait on dismissal |
| iPhone | player | landscape | landscape-right on presentation |
| iPad | browsing | all | none |
| iPad | player | all | none |

`OrientationManager` retains lifecycle coordination, but delegates masks and geometry decisions to the pure policy. `AppDelegate` asks for the mask associated with the window's idiom. This keeps iPhone behavior intact while preventing iPad rotation forcing and cross-window geometry fights.

### Storefront evidence

Deterministic mock mode generates a fictional four-image 13-inch portrait set (`2064x2752`) for Home, Library, Detail, and Settings. UI tests first prove the native split shell, adaptive frames, orientation continuity, and player containment on iPad Pro 13-inch and iPad mini simulators. A human visual review rejects clipping, empty/loading states, compatibility-mode phone UI, real account/server/media data, or test overlays.

## Verification Strategy

Work proceeds in RED/GREEN cycles:

1. Change the release preflight so the current iPhone-only tree fails the new universal contract.
2. Add pure orientation and root-layout tests before implementation.
3. Add deterministic iPad UI tests before fixing any observed layout defect.
4. Regenerate from `project.yml`, then run focused and full iPhone, large-iPad, small-iPad, and unchanged-tvOS gates on the 26.5 runtimes.
5. Re-query build `17`, use Xcode 26.6 only after its license is already accepted, archive locally, and inspect version, bundle identifier, device families, orientations, signing, and entitlements.

Swift changes are compiled by a Swift 6 toolchain. This iPad slice does not add an unrelated project-wide language-mode migration; any future change to the repository's declared `SWIFT_VERSION` needs its own full concurrency migration and design.

## Release Boundary

This workstream does not upload an IPA, attach tester groups, submit Beta App Review, change App Store metadata, or publish a tvOS build. Its final output is a locally validated iOS archive and a factual handoff to the parent release workstream. A future upload requires all of the following to be fresh at that time:

- complete security remediation and security verification;
- green release preflight and full device regression matrix;
- an unused iOS build number confirmed again in App Store Connect;
- valid Apple distribution identity/profile and `asc` authentication;
- explicit release execution under the repository TestFlight skill.

## Alternatives Rejected

### Force iPad full-screen or landscape

Adding `UIRequiresFullScreen` or forcing landscape would simplify orientation handling, but would undermine iPad multitasking and dynamic resizing and make the product behave like an enlarged phone application.

### Build a bespoke three-column tablet application now

A permanent source/library/detail architecture could become a future premium differentiator, but it expands navigation state, deep links, restoration, and test scope immediately before release. The existing two-column shell is the smallest credible native-iPad delivery.

### Change the shared build number

Updating the global `CURRENT_PROJECT_VERSION` would also advance tvOS. That conflicts with the requirement that tvOS remain unchanged, so the iOS app receives a target-specific candidate build instead.

## Risks and Controls

- **Compatibility-mode false green:** an iPad simulator can launch an iPhone-only target. Control with `UIDeviceFamily = [1,2]` inspection and native-sidebar UI assertions.
- **Build-number race:** build `17` can become occupied between planning and archive. Control with two App Store Connect queries and a hard stop; never silently reuse or replace a build.
- **Resizable-window clipping:** two full-screen device classes do not cover every Stage Manager width. Control with size-class unit tests, Pro/mini extremes, rotation, and compact fallback; retain a real-device Stage Manager pass as a release recommendation.
- **Orientation regression:** the singleton currently forces rotation. Control with a pure matrix, geometry-callback mutation proof, and player UI tests in both orientations.
- **tvOS collateral change:** shared source and XcodeGen output can drift. Control with before/after effective build settings, generated diff review, and full tvOS build/test.
- **Distribution tool mismatch:** beta Xcode can test current runtimes, but distribution must prefer Xcode 26.6. Control with an explicit license/version gate and archive commands pinned to the distribution path.
- **Storefront leakage:** screenshots can expose personal libraries or accounts. Control by using only deterministic fictional mock data and reviewing every image at original resolution.
- **Security incompleteness:** a green iPad archive is not authorization to publish. Control with an explicit no-upload terminal state and handoff to the security-gated parent release.

## Explicitly Deferred

- bespoke three-column information architecture;
- multiple content windows, drag-and-drop, keyboard command, or pointer enhancement projects;
- Mac Catalyst or Designed-for-iPad-on-Mac support;
- separate tvOS archive or build-number change;
- TestFlight/App Store upload or submission;
- unrelated codec, playback-engine, or Swift language-mode migrations.
