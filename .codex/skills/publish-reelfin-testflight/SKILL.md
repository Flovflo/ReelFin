---
name: publish-reelfin-testflight
description: Use when preparing, archiving, uploading, distributing, or checking ReelFin beta builds through TestFlight, App Store Connect, asc, xcodebuild, internal/external tester groups, public links, or Beta App Review.
---

# Publish ReelFin TestFlight

## Overview

Use this skill to ship ReelFin beta builds repeatably without relying on Xcode Accounts. Prefer the App Store Connect API key configured in `asc`, keep secrets out of output, and stop before Beta App Review if live Jellyfin review credentials are missing.

## Fixed Context

- Repo: `/Users/florian/Documents/Projet/ReelFin`
- App Store Connect app ID: `6762079357`
- Bundle ID: `com.reelfin.app`
- Team ID: `WZ4CHJH7TA`
- Internal group: `Internal Testers`
- External group: `External Testers`
- Public link: `https://testflight.apple.com/join/TkVVXmU2`
- Release source of truth: `project.yml`

## Release Workflow

1. Inspect worktree first and preserve unrelated user changes:

```bash
git status --short
VERSION=$(awk '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
BUILD=$(awk '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' project.yml)
ARCHIVE_PATH=".artifacts/TestFlight/ReelFin-iOS-${VERSION}-${BUILD}.xcarchive"
```

2. Regenerate and run release preflight:

```bash
xcodegen generate
scripts/preflight_testflight_release.sh
```

3. Run focused validation before upload:

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' -derivedDataPath .artifacts/DerivedData-testflight-ios
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2' -derivedDataPath .artifacts/DerivedData-testflight-tvos
```

4. Archive the iOS universal app for App Store Connect:

```bash
mkdir -p .artifacts/TestFlight
xcodebuild archive -project ReelFin.xcodeproj -scheme ReelFin -configuration Release -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" -derivedDataPath .artifacts/DerivedData-testflight-archive
```

After archive, verify `CFBundleShortVersionString`, `CFBundleVersion`, `UIDeviceFamily`, and `ITSAppUsesNonExemptEncryption` from the archived app `Info.plist`.

## Signing And Export

Use `asc doctor` before assuming auth is broken:

```bash
asc doctor
asc apps list --bundle-id com.reelfin.app --output json
security find-identity -v -p codesigning
```

If Xcode export/upload fails with missing App Store Connect account, continue with `asc`; the `ReelFin Admin` keychain profile is the expected path. If no `iPhone Distribution` identity is present, create one without revoking existing certs:

```bash
mkdir -p .artifacts/TestFlight/signing-new
asc certificates csr generate --common-name "ReelFin TestFlight Distribution" --key-out .artifacts/TestFlight/signing-new/ReelFinDistribution.key --csr-out .artifacts/TestFlight/signing-new/ReelFinDistribution.csr
asc certificates create --certificate-type IOS_DISTRIBUTION --csr .artifacts/TestFlight/signing-new/ReelFinDistribution.csr --pretty > .artifacts/TestFlight/signing-new/certificate.json
```

Decode the returned `certificateContent`, import the `.key` and `.cer` into the login keychain, create/download an `IOS_APP_STORE` provisioning profile for bundle resource `AG2J4CF4DG`, install it under `~/Library/MobileDevice/Provisioning Profiles/`, then delete the temporary private key and CSR from `.artifacts`:

```bash
CERT_ID=$(plutil -extract data.id raw -o - .artifacts/TestFlight/signing-new/certificate.json)
CERT_B64=$(plutil -extract data.attributes.certificateContent raw -o - .artifacts/TestFlight/signing-new/certificate.json)
printf '%s' "$CERT_B64" | base64 --decode > .artifacts/TestFlight/signing-new/ReelFinDistribution.cer
security import .artifacts/TestFlight/signing-new/ReelFinDistribution.key -k "$HOME/Library/Keychains/login.keychain-db" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild -T /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
security import .artifacts/TestFlight/signing-new/ReelFinDistribution.cer -k "$HOME/Library/Keychains/login.keychain-db" -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild -T /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
PROFILE_NAME="ReelFin App Store $(date +%Y%m%d)"
asc profiles create --name "$PROFILE_NAME" --profile-type IOS_APP_STORE --bundle AG2J4CF4DG --certificate "$CERT_ID" --pretty > .artifacts/TestFlight/signing-new/profile.json
PROFILE_ID=$(plutil -extract data.id raw -o - .artifacts/TestFlight/signing-new/profile.json)
asc profiles download --id "$PROFILE_ID" --output .artifacts/TestFlight/signing-new/ReelFin-App-Store.mobileprovision
security cms -D -i .artifacts/TestFlight/signing-new/ReelFin-App-Store.mobileprovision > .artifacts/TestFlight/signing-new/ReelFin-App-Store.plist
PROFILE_UUID=$(plutil -extract UUID raw -o - .artifacts/TestFlight/signing-new/ReelFin-App-Store.plist)
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
cp .artifacts/TestFlight/signing-new/ReelFin-App-Store.mobileprovision "$HOME/Library/MobileDevice/Provisioning Profiles/${PROFILE_UUID}.mobileprovision"
rm -f .artifacts/TestFlight/signing-new/ReelFinDistribution.key .artifacts/TestFlight/signing-new/ReelFinDistribution.csr
```

Export an IPA using a manual App Store Connect export options plist with:

```plist
method = app-store-connect
destination = export
teamID = WZ4CHJH7TA
signingStyle = manual
signingCertificate = iPhone Distribution
provisioningProfiles.com.reelfin.app = PROFILE_NAME
testFlightInternalTestingOnly = false
manageAppVersionAndBuildNumber = false
```

Then run:

```bash
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath .artifacts/TestFlight/export-ipa -exportOptionsPlist .artifacts/TestFlight/ExportOptions-app-store-connect-manual.plist
```

## Upload And Distribution

Do not pass `--notify`; this setup rejects it when adding groups.

```bash
asc builds find --app 6762079357 --build-number "$BUILD" --pretty
asc publish testflight --app 6762079357 --ipa .artifacts/TestFlight/export-ipa/ReelFin.ipa --group "Internal Testers,External Testers" --version "$VERSION" --build-number "$BUILD" --test-notes "Sign in to a Jellyfin server, browse Home and Search, open detail pages, and validate playback start, resume state, subtitle selection, and playback stability on iPhone, iPad, and Apple TV." --locale en-US --wait --timeout 60m --pretty
```

If upload succeeds but group attachment fails, find the build ID and rerun without uploading:

```bash
asc publish testflight --app 6762079357 --build BUILD_ID --group "Internal Testers,External Testers" --wait --test-notes "Sign in to a Jellyfin server, browse Home and Search, open detail pages, and validate playback start, resume state, subtitle selection, and playback stability on iPhone, iPad, and Apple TV." --locale en-US --pretty
```

## Final Checks

```bash
asc builds find --app 6762079357 --build-number "$BUILD" --pretty
asc testflight distribution view --build BUILD_ID --pretty
asc builds test-notes list --build BUILD_ID --pretty
asc testflight groups list --app 6762079357 --pretty
```

Report build ID, processing state, internal/external TestFlight states, public link, and any review blocker. `internalBuildState=IN_BETA_TESTING` means internal testers can install. `externalBuildState=READY_FOR_BETA_SUBMISSION` means the public link exists but external testers still need Beta App Review approval.

For Apple TV binary uploads, repeat the archive/export/upload flow with scheme `ReelFinTV`, destination `generic/platform=tvOS`, and `asc publish testflight --platform TV_OS` only when the user explicitly asks for the tvOS binary. The standard gate still runs `ReelFinTV` tests before the iOS universal upload.

## Beta App Review

Never invent review credentials and never print passwords. Use `Docs/AppReview-Notes.md` as the worksheet. Before submitting external beta review, require:

- contact phone number
- live Jellyfin review server URL
- dedicated review username
- dedicated review password

Update review details and submit only when those values are real:

```bash
asc testflight review edit --id 6762079357 --contact-first-name Florian --contact-last-name Taffin --contact-email florian.taffin.pro@gmail.com --contact-phone "PHONE" --demo-account-required true --demo-account-name "USERNAME" --demo-account-password "PASSWORD" --notes "SERVER URL: https://example.invalid. ReelFin is a native client for self-hosted Jellyfin servers. The app does not provide or sell media content and does not use in-app purchase. Sign in with the supplied review account, browse Home/Search/detail pages, and validate playback, resume state, subtitles, and account settings."
asc testflight review submit --build BUILD_ID --confirm --pretty
```
