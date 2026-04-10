#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURES=0
SEARCH_BIN="$(command -v rg || command -v grep || true)"
SIPS_BIN="${SIPS_BIN:-/usr/bin/sips}"
AWK_BIN="${AWK_BIN:-/usr/bin/awk}"
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

check_dimensions() {
  local file="$1"
  local expected_width="$2"
  local expected_height="$3"
  local output
  local width
  local height

  output="$("$SIPS_BIN" -g pixelWidth -g pixelHeight "$file" 2>/dev/null)"
  width="$(echo "$output" | "$AWK_BIN" '/pixelWidth/ { print $2 }')"
  height="$(echo "$output" | "$AWK_BIN" '/pixelHeight/ { print $2 }')"

  if [[ "$width" == "$expected_width" && "$height" == "$expected_height" ]]; then
    pass "Screenshot size OK for ${file#$ROOT_DIR/}"
  else
    fail "Unexpected screenshot size for ${file#$ROOT_DIR/}: got ${width}x${height}, expected ${expected_width}x${expected_height}"
  fi
}

echo "Running ReelFin TestFlight preflight..."

require_file "project.yml"
require_file "ReelFinApp/Resources/PrivacyInfo.xcprivacy"
require_file "Docs/AppStore-Submission.md"
require_file "Docs/TestFlight-Launch-Checklist.md"
require_file "Docs/AppReview-Notes.md"

require_contains "project.yml" "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO" "Export compliance flag is set"
require_contains "project.yml" "https://flovflo.github.io/reelfin-site/privacy.html" "Privacy Policy URL points to public site"
require_contains "project.yml" "https://flovflo.github.io/reelfin-site/terms.html" "Terms URL points to public site"
require_contains "project.yml" "https://flovflo.github.io/reelfin-site/support.html" "Support URL points to public site"
reject_contains "project.yml" "github.com/Flovflo/ReelFin/blob/main/Docs" "Project config no longer points to GitHub blob URLs"
require_contains "README.md" "https://github.com/Flovflo/reelfin-site" "README links to the external site repo"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-server-url>" "App review notes no longer contain placeholder server URL text"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-username>" "App review notes no longer contain placeholder username text"
reject_contains "Docs/AppReview-Notes.md" "<replace-with-review-password>" "App review notes no longer contain placeholder password text"
require_contains "Docs/privacy-policy.html" "Authentication tokens are stored only in the iOS Keychain." "Privacy policy documents Keychain-only token storage"
require_contains "Docs/privacy-policy.html" "<h2>Retention</h2>" "Privacy policy includes a retention section"
require_url "https://flovflo.github.io/reelfin-site/" "Marketing site is reachable over HTTPS"
require_url "https://flovflo.github.io/reelfin-site/privacy.html" "Privacy Policy page is reachable over HTTPS"
require_url "https://flovflo.github.io/reelfin-site/terms.html" "Terms page is reachable over HTTPS"
require_url "https://flovflo.github.io/reelfin-site/support.html" "Support page is reachable over HTTPS"

for path in \
  "AppStore/Screenshots/iphone-17-pro-max/01-home.png" \
  "AppStore/Screenshots/iphone-17-pro-max/02-library.png" \
  "AppStore/Screenshots/iphone-17-pro-max/03-detail.png" \
  "AppStore/Screenshots/iphone-17-pro-max/04-settings.png"
do
  require_file "$path"
  check_dimensions "$ROOT_DIR/$path" 1320 2868
done

for path in \
  "AppStore/Screenshots/iphone-16-pro/01-home.png" \
  "AppStore/Screenshots/iphone-16-pro/02-library.png" \
  "AppStore/Screenshots/iphone-16-pro/03-detail.png" \
  "AppStore/Screenshots/iphone-16-pro/04-settings.png"
do
  require_file "$path"
  check_dimensions "$ROOT_DIR/$path" 1206 2622
done

for path in \
  "AppStore/Screenshots/ipad-pro-13-inch-m5/01-home.png" \
  "AppStore/Screenshots/ipad-pro-13-inch-m5/02-library.png" \
  "AppStore/Screenshots/ipad-pro-13-inch-m5/03-detail.png" \
  "AppStore/Screenshots/ipad-pro-13-inch-m5/04-settings.png"
do
  require_file "$path"
  check_dimensions "$ROOT_DIR/$path" 2064 2752
done

if (( FAILURES > 0 )); then
  echo
  echo "Preflight completed with $FAILURES failure(s)."
  exit 1
fi

echo
echo "Preflight completed successfully."
