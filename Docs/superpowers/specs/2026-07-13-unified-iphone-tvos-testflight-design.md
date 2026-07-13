# Unified iPhone and Apple TV TestFlight Design

## Objective

Ship ReelFin as one product in App Store Connect and TestFlight, available only as an iPhone-native app and an Apple TV-native app. Both platform builds must use the same app record, bundle identifier, marketing version, and build number.

For the current release, both devices must show ReelFin `0.1.1 (12)`.

## Apple Distribution Model

ReelFin remains one App Store Connect app:

- App Store Connect app ID: `6762079357`
- Bundle identifier: `com.reelfin.app`
- Marketing version: `0.1.1`
- Build number: `12`

Apple does not support one IPA that runs on both iOS and tvOS. The unified product therefore contains two native binaries under the same app record:

- one iOS archive and IPA for iPhone;
- one tvOS archive and IPA for Apple TV.

TestFlight selects the correct binary for the tester's device. Publishing only the tvOS binary cannot update the version shown on iPhone.

## Platform Boundaries

The iOS app target must be explicitly restricted to iPhone SDKs and device family `1`. Mac Catalyst, Designed for iPhone/iPad on Mac, and Designed for iPhone/iPad on visionOS must be disabled.

The tvOS app target must remain restricted to Apple TV SDKs and device family `3`.

Native iPad support is excluded. Apple may still allow an iPhone-only app to run on iPad in compatibility mode; Apple provides no supported distribution switch that blocks that compatibility mode without misrepresenting hardware requirements.

No macOS build or separate Mac App Store version will be created.

## Source-of-Truth Changes

`project.yml` remains the only project configuration source. It will:

- keep the shared global `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` used by both app targets;
- disable Mac Catalyst for the iOS app and its iOS-only frameworks/tests;
- remove Mac-specific bundle and device-family overrides;
- disable Mac- and visionOS-designed compatibility on the iOS app;
- explicitly declare `iphoneos iphonesimulator` for the iOS app and `appletvos appletvsimulator` for the tvOS app;
- preserve `TARGETED_DEVICE_FAMILY = 1` for iPhone and `3` for Apple TV.

The preflight script will reject future releases that re-enable Catalyst, iPad-native device family `2`, Mac-designed compatibility, or visionOS-designed compatibility.

## Current Release Flow

The already-uploaded tvOS `0.1.1 (12)` build remains valid. After the target restrictions pass validation, ReelFin will archive and upload a new iOS `0.1.1 (12)` IPA to the same App Store Connect app. App Store Connect already confirms that build number `12` is available for the iOS `0.1.1` train and that identical build numbers may coexist across iOS and tvOS.

The iOS build will be attached to the existing Internal Testers and External Testers groups. External availability may require its own Beta App Review even though the tvOS build has already been submitted.

## Verification

Before upload:

- regenerate the Xcode project with XcodeGen;
- run the TestFlight preflight script;
- verify effective Release build settings for both app schemes;
- run the iPhone and Apple TV simulator test gates;
- archive the iOS app and verify bundle ID, version, build number, `UIDeviceFamily = [1]`, export compliance, provisioning profile, and distribution signature;
- confirm the tvOS build remains `0.1.1 (12)`, `TV_OS`, and `VALID` in App Store Connect.

After upload:

- confirm the iOS build is `0.1.1 (12)`, `IOS`, and `VALID`;
- confirm both beta groups are attached;
- confirm internal TestFlight availability;
- submit external Beta App Review only with the existing real review credentials;
- confirm that App Store Connect contains no `MAC_OS` build or version for ReelFin;
- leave the worktree clean.

## Failure Handling

The release stops before upload if platform restrictions, simulator tests, archive metadata, provisioning, or code signing fail. It stops after upload without claiming external availability if Apple reports processing failure or if Beta App Review is still pending. Existing tester accounts, Jellyfin authentication, simulator state, and App Store Connect credentials are preserved.
