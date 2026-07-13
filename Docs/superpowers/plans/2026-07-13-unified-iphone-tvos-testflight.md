# Unified iPhone and Apple TV TestFlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish ReelFin `0.1.1 (12)` as one App Store Connect product with aligned iPhone and Apple TV builds while excluding native iPad, Mac Catalyst, Designed-for-Mac, and Designed-for-visionOS support.

**Architecture:** `project.yml` remains the shared version and target source of truth. The iPhone and Apple TV targets keep one bundle identifier and one App Store Connect record, while Apple receives one platform-specific IPA per SDK. Release preflight guards prevent future platform drift before either archive is uploaded.

**Tech Stack:** XcodeGen, Swift/Xcode build settings, zsh release checks, `xcodebuild`, App Store Connect CLI (`asc`), TestFlight.

## Global Constraints

- App Store Connect app ID is `6762079357`.
- Both app targets use bundle identifier `com.reelfin.app`.
- Both platform trains use marketing version `0.1.1` and build number `12` for this release.
- iOS supports iPhone only with `TARGETED_DEVICE_FAMILY = 1` and iPhone SDKs only.
- tvOS supports Apple TV only with `TARGETED_DEVICE_FAMILY = 3` and Apple TV SDKs only.
- Mac Catalyst, Designed for iPhone/iPad on Mac, and Designed for iPhone/iPad on visionOS are disabled.
- No iPad-native device family `2`, macOS build, or separate bundle identifier is introduced.
- Preserve the authenticated tvOS simulator and Jellyfin session; never erase, uninstall, reset, or sign out.
- Do not pass `--notify` when attaching TestFlight groups.
- Do not print App Store Connect or Jellyfin credentials.

---

### Task 1: Enforce iPhone and Apple TV Platform Boundaries

**Files:**
- Modify: `scripts/preflight_testflight_release.sh`
- Modify: `project.yml`
- Modify: `PLANS.md`
- Modify: `OPTIMIZATION_AUDIT.md`

**Interfaces:**
- Consumes: XcodeGen settings in `project.yml` and the existing `require_contains`/`reject_contains` preflight helpers.
- Produces: explicit platform build settings and release checks that fail if unsupported Apple platforms are re-enabled.

- [ ] **Step 1: Add failing release assertions**

Add these checks beside the existing device-family checks in `scripts/preflight_testflight_release.sh`:

```zsh
reject_contains "project.yml" "SUPPORTS_MACCATALYST: YES" "Mac Catalyst is disabled repo-wide"
require_contains "project.yml" "SUPPORTS_MACCATALYST: NO" "iOS targets explicitly disable Mac Catalyst"
require_contains "project.yml" "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO" "Designed for iPhone/iPad on Mac is disabled"
require_contains "project.yml" "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO" "Designed for iPhone/iPad on visionOS is disabled"
require_contains "project.yml" 'SUPPORTED_PLATFORMS: "iphoneos iphonesimulator"' "iOS app uses iPhone SDKs only"
require_contains "project.yml" 'SUPPORTED_PLATFORMS: "appletvos appletvsimulator"' "tvOS app uses Apple TV SDKs only"
```

- [ ] **Step 2: Run the preflight and verify RED**

Run:

```bash
scripts/preflight_testflight_release.sh
```

Expected: non-zero exit with failures for Mac Catalyst, visionOS-designed compatibility, and explicit supported-platform declarations. Existing device-family checks must remain green.

- [ ] **Step 3: Apply the minimal target restrictions**

In `ReelFinApp.settings.base`, replace the Mac-specific block with:

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.reelfin.app
PRODUCT_NAME: ReelFin
SUPPORTED_PLATFORMS: "iphoneos iphonesimulator"
SUPPORTS_MACCATALYST: NO
SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO
TARGETED_DEVICE_FAMILY: "1"
```

Remove these obsolete keys:

```yaml
DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER: NO
PRODUCT_BUNDLE_IDENTIFIER[sdk=macosx*]: com.reelfin.mac
TARGETED_DEVICE_FAMILY[sdk=macosx*]: "6"
```

Replace every remaining iOS framework/test `SUPPORTS_MACCATALYST: YES` entry with `SUPPORTS_MACCATALYST: NO`. Add this explicit SDK restriction to `ReelFinTVApp.settings.base`:

```yaml
SUPPORTED_PLATFORMS: "appletvos appletvsimulator"
```

Keep the global version settings and both `PRODUCT_BUNDLE_IDENTIFIER: com.reelfin.app` declarations unchanged.

- [ ] **Step 4: Regenerate and verify GREEN**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodegen generate
scripts/preflight_testflight_release.sh
```

Expected: XcodeGen succeeds and every preflight assertion passes.

- [ ] **Step 5: Verify effective Release settings**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project ReelFin.xcodeproj -scheme ReelFin -configuration Release -destination 'generic/platform=iOS' -showBuildSettings | rg '^\s+(CURRENT_PROJECT_VERSION|MARKETING_VERSION|PRODUCT_BUNDLE_IDENTIFIER|SUPPORTED_PLATFORMS|SUPPORTS_MACCATALYST|SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD|SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD|TARGETED_DEVICE_FAMILY) ='
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project ReelFin.xcodeproj -scheme ReelFinTV -configuration Release -destination 'generic/platform=tvOS' -showBuildSettings | rg '^\s+(CURRENT_PROJECT_VERSION|MARKETING_VERSION|PRODUCT_BUNDLE_IDENTIFIER|SUPPORTED_PLATFORMS|SUPPORTS_MACCATALYST|TARGETED_DEVICE_FAMILY) ='
```

Expected iOS: `0.1.1`, `12`, `com.reelfin.app`, iPhone SDKs, family `1`, and every compatibility setting `NO`. Expected tvOS: `0.1.1`, `12`, `com.reelfin.app`, Apple TV SDKs, and family `3`.

- [ ] **Step 6: Record the release-boundary change**

Append a dated entry to `PLANS.md` and `OPTIMIZATION_AUDIT.md` stating that the unified release keeps one App Store record while restricting the binaries to iPhone and Apple TV, with the preflight and effective-build-setting evidence from Steps 4-5.

- [ ] **Step 7: Commit the platform restriction**

```bash
git add project.yml scripts/preflight_testflight_release.sh PLANS.md OPTIMIZATION_AUDIT.md ReelFin.xcodeproj/project.pbxproj
git commit -m "build: restrict ReelFin to iPhone and Apple TV"
```

---

### Task 2: Run Unified Release Gates

**Files:**
- Verify only: `ReelFin.xcodeproj`
- Evidence: `.artifacts/DerivedData-unified-ios`
- Evidence: `.artifacts/DerivedData-unified-tvos`

**Interfaces:**
- Consumes: the regenerated `ReelFin` and `ReelFinTV` schemes.
- Produces: fresh build/test evidence for the exact unified source revision that will be archived.

- [ ] **Step 1: Resolve available simulator destinations**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -showdestinations -project ReelFin.xcodeproj -scheme ReelFin
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -showdestinations -project ReelFin.xcodeproj -scheme ReelFinTV
```

Select the installed iPhone 17 simulator and the already-authenticated Apple TV 4K (3rd generation) simulator. Do not create, reset, or erase a simulator.

- [ ] **Step 2: Run the complete iPhone test gate**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .artifacts/DerivedData-unified-ios
```

Expected: `** TEST SUCCEEDED **`; live-fixture tests may skip only when explicitly marked as requiring unavailable live state.

- [ ] **Step 3: Run the complete Apple TV test gate**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' -derivedDataPath .artifacts/DerivedData-unified-tvos
```

Expected: `** TEST SUCCEEDED **`, including the authenticated Jellyfin player/UI tests. Preserve the current simulator container and login.

- [ ] **Step 4: Re-run preflight after tests**

```bash
scripts/preflight_testflight_release.sh
git status --short
```

Expected: preflight passes and only known generated scheme churn may appear.

---

### Task 3: Archive and Export the iPhone 0.1.1 (12) IPA

**Files:**
- Create artifact: `.artifacts/TestFlight/ReelFin-iOS-0.1.1-12.xcarchive`
- Create artifact: `.artifacts/TestFlight/ExportOptions-iOS-12.plist`
- Create artifact: `.artifacts/TestFlight/export-iOS-0.1.1-12/ReelFin.ipa`

**Interfaces:**
- Consumes: valid Apple Distribution identity, iOS App Store provisioning profile, and the exact tested commit.
- Produces: distribution-signed iPhone-only IPA with version `0.1.1 (12)`.

- [ ] **Step 1: Confirm App Store Connect numbering and signing resources**

```bash
asc builds next-build-number --app 6762079357 --version 0.1.1 --platform IOS --initial-build-number 12 --output json --pretty
security find-identity -v -p codesigning
asc profiles view --id ZRPA5W6G6F --include bundleId,certificates --output json | jq '{id:.data.id,name:.data.attributes.name,platform:.data.attributes.platform,type:.data.attributes.profileType,state:.data.attributes.profileState,expires:.data.attributes.expirationDate,bundleId:(.included[]|select(.type=="bundleIds")|.attributes.identifier),certificateIds:[.included[]|select(.type=="certificates")|.id]}'
```

Expected: the next iOS build is `12`, a valid distribution identity exists, and a non-expired iOS App Store profile is available. Create a new profile through `asc` only if no valid matching profile exists; do not revoke an existing certificate.

- [ ] **Step 2: Archive the iPhone target**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild archive -project ReelFin.xcodeproj -scheme ReelFin -configuration Release -destination 'generic/platform=iOS' -archivePath .artifacts/TestFlight/ReelFin-iOS-0.1.1-12.xcarchive -derivedDataPath .artifacts/DerivedData-testflight-unified-ios -allowProvisioningUpdates
```

Expected: `** ARCHIVE SUCCEEDED **`.

- [ ] **Step 3: Verify archived metadata before export**

Inspect `Products/Applications/ReelFin.app/Info.plist` with `PlistBuddy` and verify:

```text
CFBundleIdentifier = com.reelfin.app
CFBundleShortVersionString = 0.1.1
CFBundleVersion = 12
UIDeviceFamily[0] = 1
MinimumOSVersion = 26.0
ITSAppUsesNonExemptEncryption = false
```

No second `UIDeviceFamily` entry may exist.

- [ ] **Step 4: Export with manual App Store signing**

Resolve the active profile name from the Step 1 response, then create `.artifacts/TestFlight/ExportOptions-iOS-12.plist`:

```bash
PROFILE_NAME="$(asc profiles view --id ZRPA5W6G6F --output json | jq -r '.data.attributes.name')"
test -n "$PROFILE_NAME"
EXPORT_OPTIONS=.artifacts/TestFlight/ExportOptions-iOS-12.plist
plutil -create xml1 "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :method string app-store-connect' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :destination string export' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :teamID string WZ4CHJH7TA' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :signingCertificate string iPhone Distribution' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :manageAppVersionAndBuildNumber bool false' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :testFlightInternalTestingOnly bool false' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :uploadSymbols bool true' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:com.reelfin.app string $PROFILE_NAME" "$EXPORT_OPTIONS"
```

Then run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -exportArchive -archivePath .artifacts/TestFlight/ReelFin-iOS-0.1.1-12.xcarchive -exportPath .artifacts/TestFlight/export-iOS-0.1.1-12 -exportOptionsPlist .artifacts/TestFlight/ExportOptions-iOS-12.plist -allowProvisioningUpdates
```

Expected: `** EXPORT SUCCEEDED **` and `ReelFin.ipa` exists.

- [ ] **Step 5: Verify the exported IPA**

Extract the IPA under a unique `.artifacts/TestFlight/verify-iOS-12.*` directory. Verify the same plist values as Step 3, decode `embedded.mobileprovision` to confirm the iOS App Store profile/team, and run:

```bash
codesign --verify --deep --strict --verbose=2 Payload/ReelFin.app
```

Expected: the signature is valid and uses the `iPhone Distribution` authority.

---

### Task 4: Publish and Verify Both Platform Trains

**Files:**
- Upload: `.artifacts/TestFlight/export-iOS-0.1.1-12/ReelFin.ipa`
- Verify remote: App Store Connect app `6762079357`

**Interfaces:**
- Consumes: verified iPhone IPA and the already-valid tvOS build ID `40d2ae5f-8813-4d64-9909-9850816b0d25`.
- Produces: aligned `IOS` and `TV_OS` TestFlight builds at `0.1.1 (12)` under one app record.

- [ ] **Step 1: Upload and distribute the iPhone IPA**

```bash
asc publish testflight --app 6762079357 --ipa .artifacts/TestFlight/export-iOS-0.1.1-12/ReelFin.ipa --group "Internal Testers,External Testers" --version 0.1.1 --build-number 12 --platform IOS --test-notes "Validate ReelFin 0.1.1 on iPhone: Jellyfin sign-in, Home/Search/Library navigation, detail transitions, resume/restart, playback seek to zero and forward, audio/subtitle selection, and playback stability. The matching Apple TV build uses the same version and build number." --locale en-US --wait --timeout 60m --output json --pretty
```

Expected: upload committed, processing state `VALID`, and both beta group IDs returned. Do not pass `--notify`.

- [ ] **Step 2: Verify the aligned platform trains**

```bash
asc builds info --app 6762079357 --build-number 12 --version 0.1.1 --platform IOS --output json --pretty
asc builds info --app 6762079357 --build-number 12 --version 0.1.1 --platform TV_OS --output json --pretty
```

Expected: two different build IDs, both `VALID`, both marketing version `0.1.1`, and both build number `12` under `com.reelfin.app`.

- [ ] **Step 3: Verify TestFlight groups and notes**

Resolve the new iOS build ID and run:

```bash
IOS_BUILD_ID="$(asc builds info --app 6762079357 --build-number 12 --version 0.1.1 --platform IOS --output json | jq -r '.data.id')"
test -n "$IOS_BUILD_ID"
asc testflight distribution view --build-id "$IOS_BUILD_ID" --output json --pretty
asc builds test-notes list --build-id "$IOS_BUILD_ID" --output json --pretty
asc testflight groups links view --group-id 6badb965-58fa-4314-bba6-e01093ec2449 --type builds --paginate --output json
asc testflight groups links view --group-id 75920230-ea55-4c21-be11-4e6262f18c5b --type builds --paginate --output json
```

Expected: internal state is ready for beta testing, notes are present, and the iOS build ID occurs in both group relationships.

- [ ] **Step 4: Submit external Beta App Review when required**

Check review-detail completeness without printing credential values. If the iOS external state is `READY_FOR_BETA_SUBMISSION` and the existing contact/demo fields are complete, run:

```bash
IOS_BUILD_ID="$(asc builds info --app 6762079357 --build-number 12 --version 0.1.1 --platform IOS --output json | jq -r '.data.id')"
asc testflight review submit --build-id "$IOS_BUILD_ID" --confirm --output json --pretty
```

Expected: `WAITING_FOR_REVIEW`. If Apple already approves or reuses review, report the actual resulting state instead.

- [ ] **Step 5: Prove there is no macOS product train**

```bash
asc builds list --app 6762079357 --platform MAC_OS --processing-state all --output json --pretty
```

Expected: zero macOS builds.

- [ ] **Step 6: Restore generated-only scheme churn and verify cleanliness**

If the only remaining diffs are XcodeGen scheme ordering changes, restore only those two generated files:

```bash
git restore ReelFin.xcodeproj/xcshareddata/xcschemes/ReelFin.xcscheme ReelFin.xcodeproj/xcshareddata/xcschemes/ReelFinTV.xcscheme
git status --short --branch
```

Expected: clean `codex/tvos-ux-polish` worktree. Do not restore any source, documentation, or user-authored change.
