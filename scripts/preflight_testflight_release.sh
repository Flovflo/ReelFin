#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0
SEARCH_BIN="$(command -v rg || command -v grep || true)"
CURL_BIN="${CURL_BIN:-$(command -v curl || true)}"

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
require_file "ReelFinApp/Resources/Info.plist"
require_file "ReelFinApp/Resources/PrivacyInfo.xcprivacy"
require_file "Docs/AppStore-Submission.md"
require_file "Docs/TestFlight-Launch-Checklist.md"
require_file "Docs/AppReview-Notes.md"

require_contains "project.yml" "TARGETED_DEVICE_FAMILY: \"1\"" "iOS app is configured for iPhone only"
require_contains "ReelFinApp/Resources/Info.plist" "<key>ITSAppUsesNonExemptEncryption</key>" "Export compliance flag is set"
require_contains "ReelFinApp/Resources/Info.plist" "https://flovflo.github.io/reelfin-site/privacy.html" "Privacy Policy URL points to public site"
require_contains "ReelFinApp/Resources/Info.plist" "https://flovflo.github.io/reelfin-site/terms.html" "Terms URL points to public site"
require_contains "ReelFinApp/Resources/Info.plist" "https://flovflo.github.io/reelfin-site/support.html" "Support URL points to public site"
reject_contains "ReelFinApp/Resources/Info.plist" "UISupportedInterfaceOrientations~ipad" "iPad orientations are removed from the iOS app plist"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-server-url>" "App review notes no longer contain placeholder server URL text"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-username>" "App review notes no longer contain placeholder username text"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-password>" "App review notes no longer contain placeholder password text"
require_contains "Docs/privacy-policy.html" "Authentication tokens are stored only in the Apple Keychain." "Privacy policy documents Keychain-only token storage"
require_contains "Docs/privacy-policy.html" "<h2>Retention</h2>" "Privacy policy includes a retention section"
reject_contains "Docs/AppStore-Submission.md" "iPad" "Submission docs no longer advertise iPad support"
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
