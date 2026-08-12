#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
PROMOTE=0

if [[ "${1:-}" == "--promote" ]]; then
  PROMOTE=1
elif [[ $# -ne 0 ]]; then
  echo "usage: $0 [--promote]" >&2
  exit 64
fi

export DEVELOPER_DIR
XCRUN="/usr/bin/xcrun"
XCODEBUILD="${DEVELOPER_DIR}/usr/bin/xcodebuild"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_ROOT="${ROOT_DIR}/.artifacts/app-store-screenshots/${TIMESTAMP}"
DERIVED_DATA="${REELFIN_SCREENSHOT_DERIVED_DATA:-${ROOT_DIR}/.artifacts/app-store-screenshots/DerivedData}"

mkdir -p "${RUN_ROOT}"
cd "${ROOT_DIR}"

resolve_udid() {
  local runtime="$1"
  local device_name="$2"
  "$XCRUN" simctl list devices available | awk -v runtime="$runtime" -v device_name="$device_name" '
    $0 == "-- " runtime " --" { in_runtime = 1; next }
    /^-- / { in_runtime = 0 }
    in_runtime && index($0, "    " device_name " (") == 1 {
      for (field = 1; field <= NF; field += 1) {
        if (length($field) == 38 && $field ~ /^\([0-9A-F-]+\)$/) {
          print substr($field, 2, 36)
          exit
        }
      }
      exit
    }
  '
}

declare -a OWNED_UDIDS=()

cleanup() {
  local udid
  for udid in ${OWNED_UDIDS[@]+"${OWNED_UDIDS[@]}"}; do
    "$XCRUN" simctl status_bar "$udid" clear >/dev/null 2>&1 || true
    "$XCRUN" simctl shutdown "$udid" >/dev/null 2>&1 || true
  done
  launchctl unsetenv DEVELOPER_DIR >/dev/null 2>&1 || true
}
trap cleanup EXIT

launchctl setenv DEVELOPER_DIR "$DEVELOPER_DIR"
xcodegen generate >/dev/null

capture_family() {
  local run_number="$1"
  local slug="$2"
  local runtime="$3"
  local device_name="$4"
  local scheme="$5"
  local test_identifier="$6"
  local expected_width="$7"
  local expected_height="$8"
  shift 8
  local expected_names=("$@")
  local udid
  local raw_root="${RUN_ROOT}/run-${run_number}/raw"
  local normalized_root="${RUN_ROOT}/run-${run_number}/normalized/${slug}"
  local result_bundle="${RUN_ROOT}/run-${run_number}/${slug}.xcresult"
  local log_file="${RUN_ROOT}/run-${run_number}/${slug}.log"

  udid="$(resolve_udid "$runtime" "$device_name")"
  if [[ -z "$udid" ]]; then
    echo "No available ${device_name} on ${runtime}." >&2
    exit 1
  fi

  OWNED_UDIDS+=("$udid")
  "$XCRUN" simctl boot "$udid" >/dev/null 2>&1 || true
  local booted=0
  local attempt
  for attempt in {1..60}; do
    if "$XCRUN" simctl list devices | grep -F "$udid" | grep -q '(Booted)'; then
      booted=1
      break
    fi
    sleep 1
  done
  if [[ "$booted" -ne 1 ]]; then
    echo "Timed out waiting for ${device_name} (${udid}) to boot." >&2
    exit 1
  fi
  if [[ "$slug" == "13-inch" ]]; then
    "$XCRUN" simctl uninstall "$udid" com.reelfin.app >/dev/null 2>&1 || true
    "$XCRUN" simctl spawn "$udid" defaults write com.apple.springboard SBChamoisWindowingEnabled -bool false
    "$XCRUN" simctl spawn "$udid" defaults write com.apple.springboard SBMedusaMultitaskingEnabled -bool false
    "$XCRUN" simctl shutdown "$udid"
    "$XCRUN" simctl boot "$udid"
    booted=0
    for attempt in {1..60}; do
      if "$XCRUN" simctl list devices | grep -F "$udid" | grep -q '(Booted)'; then
        booted=1
        break
      fi
      sleep 1
    done
    if [[ "$booted" -ne 1 ]]; then
      echo "Timed out restarting ${device_name} in full-screen mode." >&2
      exit 1
    fi
  fi
  if [[ "$slug" != "tvOS" ]]; then
    "$XCRUN" simctl status_bar "$udid" override \
      --time 9:41 --dataNetwork wifi --wifiBars 3 \
      --cellularMode active --cellularBars 4 \
      --batteryState charged --batteryLevel 100
  fi

  mkdir -p "$raw_root" "$normalized_root"
  TEST_RUNNER_REELFIN_SCREENSHOT_OUTPUT_DIR="$raw_root" \
  TEST_RUNNER_REELFIN_SCREENSHOT_DEVICE_SLUG="$slug" \
  "$XCODEBUILD" test \
    -project ReelFin.xcodeproj \
    -scheme "$scheme" \
    -destination "id=${udid}" \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO \
    -only-testing:"$test_identifier" \
    2>&1 | tee "$log_file"

  local name
  for name in "${expected_names[@]}"; do
    local source_png="${raw_root}/${slug}/${name}.png"
    local destination_png="${normalized_root}/${name}.png"
    if [[ ! -f "$source_png" ]]; then
      echo "Missing expected capture: ${source_png}" >&2
      exit 1
    fi
    "$XCRUN" swift scripts/prepare_storefront_png.swift \
      "$source_png" "$destination_png" "$expected_width" "$expected_height"
    local alpha
    alpha="$(sips -g hasAlpha "$destination_png" 2>/dev/null | awk '/hasAlpha:/ {print $2; exit}')"
    if [[ "$alpha" != "no" ]]; then
      echo "Storefront PNG still has alpha: ${destination_png}" >&2
      exit 1
    fi
  done

  "$XCRUN" simctl status_bar "$udid" clear >/dev/null 2>&1 || true
  "$XCRUN" simctl shutdown "$udid" >/dev/null 2>&1 || true
}

run_capture_matrix() {
  local run_number="$1"
  capture_family "$run_number" "6.9-inch" "iOS 26.5" "iPhone 17 Pro Max" \
    "ReelFin" "ReelFinUITests/AppStoreScreenshotTests/testCaptureScreenshots" \
    1320 2868 "01-home" "02-library" "03-detail" "04-settings"
  capture_family "$run_number" "13-inch" "iOS 26.5" "iPad Pro 13-inch (M5)" \
    "ReelFin" "ReelFinUITests/AppStoreScreenshotTests/testCaptureScreenshots" \
    2064 2752 "01-home" "02-library" "03-detail" "04-settings"
  capture_family "$run_number" "tvOS" "tvOS 26.5" "Apple TV 4K (3rd generation) (at 1080p)" \
    "ReelFinTV" "ReelFinTVUITests/TVAppStoreScreenshotTests/testCaptureFictionalStorefrontScreenshots" \
    1920 1080 "01-home" "02-library" "03-detail" "04-search"
}

run_capture_matrix 1
run_capture_matrix 2

for slug in "6.9-inch" "13-inch" "tvOS"; do
  diff -rq "${RUN_ROOT}/run-1/normalized/${slug}" "${RUN_ROOT}/run-2/normalized/${slug}"
done

if [[ "$PROMOTE" -eq 1 ]]; then
  for slug in "6.9-inch" "13-inch" "tvOS"; do
    destination="${ROOT_DIR}/Docs/Media/AppStoreReady/${slug}/screenshots"
    mkdir -p "$destination"
    cp "${RUN_ROOT}/run-1/normalized/${slug}/"*.png "$destination/"
  done
fi

echo "Validated two pixel-identical fictional storefront runs."
echo "Artifacts: ${RUN_ROOT}"
if [[ "$PROMOTE" -eq 1 ]]; then
  echo "Promoted validated assets under Docs/Media/AppStoreReady/."
else
  echo "Assets were not promoted; rerun with --promote after visual review."
fi
