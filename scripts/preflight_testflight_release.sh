#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0
SEARCH_BIN="$(command -v rg || command -v grep || true)"
CURL_BIN="${CURL_BIN:-$(command -v curl || true)}"
APP_INFO_PLIST="ReelFinApp/App/Info.plist"
APP_PRIVACY_MANIFEST="ReelFinApp/Resources/PrivacyInfo.xcprivacy"
TV_TOP_SHELF_WIDE_CONTENTS="ReelFinApp/Resources/Assets.xcassets/AppIcon.brandassets/Top Shelf Image Wide.imageset/Contents.json"
TV_TOP_SHELF_WIDE_2X="ReelFinApp/Resources/Assets.xcassets/AppIcon.brandassets/Top Shelf Image Wide.imageset/topshelf-wide@2x.png"

pass() {
  echo "[PASS] $1"
}

fail() {
  echo "[FAIL] $1"
  FAILURES=$((FAILURES + 1))
}

require_file() {
  local path="$1"
  if [[ -f "$ROOT_DIR/$path" ]]; then
    pass "Found $path"
  else
    fail "Missing $path"
  fi
}

require_image_dimensions() {
  local asset_path="$1"
  local expected_width="$2"
  local expected_height="$3"
  local label="$4"
  local actual_width
  local actual_height

  if [[ ! -f "$ROOT_DIR/$asset_path" ]]; then
    fail "$label"
    return
  fi

  actual_width="$(/usr/bin/sips -g pixelWidth "$ROOT_DIR/$asset_path" 2>/dev/null | awk '/pixelWidth:/ { print $2; exit }')"
  actual_height="$(/usr/bin/sips -g pixelHeight "$ROOT_DIR/$asset_path" 2>/dev/null | awk '/pixelHeight:/ { print $2; exit }')"

  if [[ "$actual_width" == "$expected_width" && "$actual_height" == "$expected_height" ]]; then
    pass "$label"
  else
    fail "$label (expected ${expected_width}x${expected_height}, found ${actual_width:-unknown}x${actual_height:-unknown})"
  fi
}

require_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [[ -n "$SEARCH_BIN" ]] && "$SEARCH_BIN" -q --fixed-strings -- "$pattern" "$ROOT_DIR/$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

require_plist_array_member() {
  local path="$1"
  local key="$2"
  local expected="$3"
  local label="$4"
  local values
  values="$(/usr/libexec/PlistBuddy -c "Print :${key}" "$ROOT_DIR/$path" 2>/dev/null || true)"
  if /usr/bin/grep -Fq -- "$expected" <<<"$values"; then
    pass "$label"
  else
    fail "$label"
  fi
}

require_distribution_xcode_ready() {
  local developer_dir="${REELFIN_DISTRIBUTION_DEVELOPER_DIR:-/Users/flo/Applications/Xcode-26.6.app/Contents/Developer}"
  local xcodebuild_path="${developer_dir}/usr/bin/xcodebuild"
  if [[ ! -x "$xcodebuild_path" ]]; then
    fail "Xcode 26.6 distribution toolchain is installed"
    return
  fi

  if DEVELOPER_DIR="$developer_dir" "$xcodebuild_path" -checkFirstLaunchStatus >/dev/null 2>&1; then
    pass "Xcode 26.6 license and first-launch setup are already complete"
  else
    fail "Xcode 26.6 requires a human to complete license/first-launch setup"
  fi
}

reject_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [[ -n "$SEARCH_BIN" ]] && "$SEARCH_BIN" -q --fixed-strings -- "$pattern" "$ROOT_DIR/$path"; then
    fail "$label"
  else
    pass "$label"
  fi
}

require_current_project_version_at_least() {
  local minimum="$1"
  local current
  current="$(awk '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$ROOT_DIR/project.yml")"

  if [[ "$current" == <-> && "$current" -ge "$minimum" ]]; then
    pass "Build number is at least $minimum for beta distribution"
  else
    fail "Build number is at least $minimum for beta distribution"
  fi
}

require_url() {
  local url="$1"
  local label="$2"
  if [[ -n "$CURL_BIN" ]] && "$CURL_BIN" --silent --show-error --fail --head "$url" >/dev/null; then
    pass "$label"
  else
    fail "$label"
  fi
}

echo "Running ReelFin TestFlight preflight..."

require_file "project.yml"
require_file "$APP_INFO_PLIST"
require_file "$APP_PRIVACY_MANIFEST"
require_file "Docs/AppStore-Submission.md"
require_file "Docs/TestFlight-Launch-Checklist.md"
require_file "Docs/AppReview-Notes.md"
require_file "Docs/privacy-policy.html"
require_file "Docs/terms-of-service.html"
require_file "Docs/support.html"
require_file "Shared/Sources/Shared/ReviewDemoMode.swift"
require_file "$TV_TOP_SHELF_WIDE_2X"

require_contains "project.yml" "CURRENT_PROJECT_VERSION: 17" "Unified build number is exactly 17"
require_contains "project.yml" "MARKETING_VERSION: 1.0" "Unified marketing version is exactly 1.0"
require_contains "project.yml" "TARGETED_DEVICE_FAMILY: \"1,2\"" "iOS app is configured for iPhone and iPad"
require_contains "project.yml" "TARGETED_DEVICE_FAMILY: \"3\"" "tvOS app is configured for Apple TV only"
reject_contains "project.yml" "UIRequiresFullScreen" "iPad multitasking is not disabled"
reject_contains "project.yml" "SUPPORTS_MACCATALYST: YES" "Mac Catalyst is disabled repo-wide"
require_contains "project.yml" "SUPPORTS_MACCATALYST: NO" "iOS targets explicitly disable Mac Catalyst"
require_contains "project.yml" "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO" "Designed for iPhone/iPad on Mac is disabled"
require_contains "project.yml" "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO" "Designed for iPhone/iPad on visionOS is disabled"
require_contains "project.yml" 'SUPPORTED_PLATFORMS: "iphoneos iphonesimulator"' "Universal app uses the iOS device and simulator SDKs"
require_contains "project.yml" 'SUPPORTED_PLATFORMS: "appletvos appletvsimulator"' "tvOS app uses Apple TV SDKs only"
require_contains "project.yml" "- Onboarding/TV" "iOS excludes tvOS-only onboarding screenshots"
require_contains "project.yml" "- path: ReelFinApp/Resources/Onboarding/TV" "tvOS embeds only tvOS onboarding screenshots"
require_contains "$APP_INFO_PLIST" "<key>ITSAppUsesNonExemptEncryption</key>" "Export compliance flag is set"
require_contains "$APP_INFO_PLIST" '<string>$(MARKETING_VERSION)</string>' "App version is sourced from MARKETING_VERSION"
require_contains "$APP_INFO_PLIST" '<string>$(CURRENT_PROJECT_VERSION)</string>' "App build is sourced from CURRENT_PROJECT_VERSION"
require_contains "$APP_INFO_PLIST" "https://flovflo.github.io/reelfin-site/privacy.html" "Privacy Policy URL points to public site"
require_contains "$APP_INFO_PLIST" "https://flovflo.github.io/reelfin-site/terms.html" "Terms URL points to public site"
require_contains "$APP_INFO_PLIST" "https://flovflo.github.io/reelfin-site/support.html" "Support URL points to public site"
require_contains "$APP_INFO_PLIST" "florian.taffin.pro@gmail.com" "Support email matches public support surface"
require_contains "$APP_INFO_PLIST" "UISupportedInterfaceOrientations~ipad" "iPad orientations are declared"
require_plist_array_member "$APP_INFO_PLIST" "UISupportedInterfaceOrientations~ipad" "UIInterfaceOrientationPortrait" "iPad supports portrait"
require_plist_array_member "$APP_INFO_PLIST" "UISupportedInterfaceOrientations~ipad" "UIInterfaceOrientationPortraitUpsideDown" "iPad supports upside-down portrait"
require_plist_array_member "$APP_INFO_PLIST" "UISupportedInterfaceOrientations~ipad" "UIInterfaceOrientationLandscapeLeft" "iPad supports landscape left"
require_plist_array_member "$APP_INFO_PLIST" "UISupportedInterfaceOrientations~ipad" "UIInterfaceOrientationLandscapeRight" "iPad supports landscape right"
require_contains "$APP_PRIVACY_MANIFEST" "NSPrivacyTracking" "Privacy manifest declares tracking status"
require_contains "$APP_PRIVACY_MANIFEST" "NSPrivacyAccessedAPICategoryUserDefaults" "Privacy manifest declares UserDefaults required-reason API"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-server-url>" "App review notes no longer contain placeholder server URL text"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-username>" "App review notes no longer contain placeholder username text"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-password>" "App review notes no longer contain placeholder password text"
require_contains "Docs/privacy-policy.html" "Authentication tokens are stored only in the Apple Keychain." "Privacy policy documents Keychain-only token storage"
require_contains "Docs/privacy-policy.html" "<h2>Retention</h2>" "Privacy policy includes a retention section"
require_contains "Docs/AppStore-Submission.md" "iPhone, iPad, and Apple TV" "Submission docs match supported platforms"
require_contains "Docs/TestFlight-Launch-Checklist.md" "External TestFlight group" "Checklist includes external TestFlight distribution"
require_contains "Docs/AppReview-Notes.md" "https://review.reelfin.app" "App review notes include the review demo server URL"
require_contains "Shared/Sources/Shared/ReviewDemoMode.swift" "review-demo-user" "Review demo mode is compiled into the app"
require_contains "$TV_TOP_SHELF_WIDE_CONTENTS" '"topshelf-wide@2x.png"' "tvOS Top Shelf Wide catalog declares its 2x image"
require_image_dimensions "$TV_TOP_SHELF_WIDE_2X" 4640 1440 "tvOS Top Shelf Wide 2x image is 4640x1440"
for screenshot in 01-home 02-library 03-detail 04-settings; do
  require_image_dimensions "Docs/Media/AppStoreReady/13-inch/screenshots/${screenshot}.png" 2064 2752 \
    "13-inch ${screenshot} screenshot is 2064x2752"
done
require_url "https://flovflo.github.io/reelfin-site/" "Marketing site is reachable over HTTPS"
require_url "https://flovflo.github.io/reelfin-site/privacy.html" "Privacy Policy page is reachable over HTTPS"
require_url "https://flovflo.github.io/reelfin-site/terms.html" "Terms page is reachable over HTTPS"
require_url "https://flovflo.github.io/reelfin-site/support.html" "Support page is reachable over HTTPS"

if [[ "${1:-}" == "--distribution-readiness" ]]; then
  require_distribution_xcode_ready
fi

if (( FAILURES > 0 )); then
  echo
  echo "Preflight completed with $FAILURES failure(s)."
  exit 1
fi

echo
echo "Preflight completed successfully."
