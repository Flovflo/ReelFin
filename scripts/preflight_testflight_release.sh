#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0
SEARCH_BIN="$(command -v rg || command -v grep || true)"
CURL_BIN="${CURL_BIN:-$(command -v curl || true)}"
APP_INFO_PLIST="ReelFinApp/App/Info.plist"
APP_PRIVACY_MANIFEST="ReelFinApp/Resources/PrivacyInfo.xcprivacy"

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

require_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [[ -n "$SEARCH_BIN" ]] && "$SEARCH_BIN" -q --fixed-strings "$pattern" "$ROOT_DIR/$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

reject_contains() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [[ -n "$SEARCH_BIN" ]] && "$SEARCH_BIN" -q --fixed-strings "$pattern" "$ROOT_DIR/$path"; then
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

require_current_project_version_at_least 10
require_contains "project.yml" "TARGETED_DEVICE_FAMILY: \"1\"" "iOS app is configured for iPhone only"
require_contains "project.yml" "TARGETED_DEVICE_FAMILY: \"3\"" "tvOS app is configured for Apple TV only"
reject_contains "project.yml" "TARGETED_DEVICE_FAMILY: \"1,2\"" "iOS app does not declare iPad support"
require_contains "$APP_INFO_PLIST" "<key>ITSAppUsesNonExemptEncryption</key>" "Export compliance flag is set"
require_contains "$APP_INFO_PLIST" '<string>$(MARKETING_VERSION)</string>' "App version is sourced from MARKETING_VERSION"
require_contains "$APP_INFO_PLIST" '<string>$(CURRENT_PROJECT_VERSION)</string>' "App build is sourced from CURRENT_PROJECT_VERSION"
require_contains "$APP_INFO_PLIST" "https://flovflo.github.io/reelfin-site/privacy.html" "Privacy Policy URL points to public site"
require_contains "$APP_INFO_PLIST" "https://flovflo.github.io/reelfin-site/terms.html" "Terms URL points to public site"
require_contains "$APP_INFO_PLIST" "https://flovflo.github.io/reelfin-site/support.html" "Support URL points to public site"
require_contains "$APP_INFO_PLIST" "florian.taffin.pro@gmail.com" "Support email matches public support surface"
reject_contains "$APP_INFO_PLIST" "UISupportedInterfaceOrientations~ipad" "iPad orientations are not declared for the iPhone-only app"
require_contains "$APP_PRIVACY_MANIFEST" "NSPrivacyTracking" "Privacy manifest declares tracking status"
require_contains "$APP_PRIVACY_MANIFEST" "NSPrivacyAccessedAPICategoryUserDefaults" "Privacy manifest declares UserDefaults required-reason API"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-server-url>" "App review notes no longer contain placeholder server URL text"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-username>" "App review notes no longer contain placeholder username text"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-password>" "App review notes no longer contain placeholder password text"
require_contains "Docs/privacy-policy.html" "Authentication tokens are stored only in the Apple Keychain." "Privacy policy documents Keychain-only token storage"
require_contains "Docs/privacy-policy.html" "<h2>Retention</h2>" "Privacy policy includes a retention section"
require_contains "Docs/AppStore-Submission.md" "iPhone and Apple TV" "Submission docs match supported platforms"
require_contains "Docs/TestFlight-Launch-Checklist.md" "External TestFlight group" "Checklist includes external TestFlight distribution"
require_contains "Docs/AppReview-Notes.md" "https://review.reelfin.app" "App review notes include the review demo server URL"
require_contains "Shared/Sources/Shared/ReviewDemoMode.swift" "review-demo-user" "Review demo mode is compiled into the app"
require_url "https://flovflo.github.io/reelfin-site/" "Marketing site is reachable over HTTPS"
require_url "https://flovflo.github.io/reelfin-site/privacy.html" "Privacy Policy page is reachable over HTTPS"
require_url "https://flovflo.github.io/reelfin-site/terms.html" "Terms page is reachable over HTTPS"
require_url "https://flovflo.github.io/reelfin-site/support.html" "Support page is reachable over HTTPS"

if (( FAILURES > 0 )); then
  echo
  echo "Preflight completed with $FAILURES failure(s)."
  exit 1
fi

echo
echo "Preflight completed successfully."
