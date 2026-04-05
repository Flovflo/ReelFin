#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION_ID="${1:-}"
ARTIFACT_ROOT="${ROOT_DIR}/.artifacts/player-ui-probe"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="${ARTIFACT_ROOT}/${TIMESTAMP}"
RESULT_BUNDLE="${RUN_DIR}/PlayerSmoke.xcresult"
LOG_CAPTURE_PID=""

mkdir -p "${RUN_DIR}"
cd "${ROOT_DIR}"

resolve_destination_id() {
  if [ -n "${DESTINATION_ID}" ]; then
    echo "${DESTINATION_ID}"
    return
  fi

  local booted
  booted="$(xcrun simctl list devices available | awk -F '[()]' '/Booted/ && /iPhone/ {print $2; exit}')"
  if [ -n "${booted}" ]; then
    echo "${booted}"
    return
  fi

  xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Pro Max/ {print $2; exit}'
}

DESTINATION_ID="$(resolve_destination_id)"
if [ -z "${DESTINATION_ID}" ]; then
  echo "No usable iPhone simulator found."
  exit 1
fi

cleanup() {
  if [ -n "${LOG_CAPTURE_PID}" ] && kill -0 "${LOG_CAPTURE_PID}" 2>/dev/null; then
    kill "${LOG_CAPTURE_PID}" 2>/dev/null || true
    wait "${LOG_CAPTURE_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "Player UI probe on simulator ${DESTINATION_ID}"
echo "Artifacts: ${RUN_DIR}"

open -a Simulator >/dev/null 2>&1 || true
xcrun simctl boot "${DESTINATION_ID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${DESTINATION_ID}" -b

echo "Regenerating project..."
xcodegen generate >/dev/null

echo "Starting ReelFin log capture..."
xcrun simctl spawn "${DESTINATION_ID}" log stream \
  --style compact \
  --level info \
  --predicate 'subsystem == "com.reelfin.app" OR process == "ReelFin"' \
  > "${RUN_DIR}/reelfin.log" 2>&1 &
LOG_CAPTURE_PID=$!

XCODEBUILD_CMD=(
  xcodebuild test
  -project ReelFin.xcodeproj
  -scheme ReelFin
  -destination "id=${DESTINATION_ID}"
  -resultBundlePath "${RESULT_BUNDLE}"
  -only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testExistingSessionMoviePlaybackSmoke
  -only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testExistingSessionSeriesPlaybackSmoke
)

echo "Running UI smoke tests..."
"${XCODEBUILD_CMD[@]}" | tee "${RUN_DIR}/xcodebuild.log"

echo "Exporting screenshots..."
xcrun xcresulttool export attachments \
  --path "${RESULT_BUNDLE}" \
  --output-path "${RUN_DIR}/attachments" >/dev/null

echo "Extracting tap log..."
rg '^\[UI-TAP\]' "${RUN_DIR}/xcodebuild.log" > "${RUN_DIR}/taps.log" || true

echo "Extracting playback summary..."
rg -n 'Playback selected method|Playback URL|avplayer.first-frame|Decoded-frame watchdog|playback.startup.failure|fallback.triggered|readyToPlay|native_player_screen' \
  "${RUN_DIR}/reelfin.log" > "${RUN_DIR}/playback-summary.log" || true

echo
echo "Player UI probe finished."
echo "Result bundle: ${RESULT_BUNDLE}"
echo "Screenshots: ${RUN_DIR}/attachments"
echo "Tap log: ${RUN_DIR}/taps.log"
echo "Playback log: ${RUN_DIR}/playback-summary.log"
