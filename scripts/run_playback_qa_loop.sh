#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOPS="${1:-1}"
DESTINATION_ID="${2:-}"
ARTIFACT_ROOT="${ROOT_DIR}/.artifacts/playback-qa"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="${ARTIFACT_ROOT}/${TIMESTAMP}"
LOG_CAPTURE_PID=""

if ! [[ "${LOOPS}" =~ ^[0-9]+$ ]] || [ "${LOOPS}" -lt 1 ]; then
  echo "Usage: $0 [loops>=1] [simulator-device-id]"
  exit 1
fi

mkdir -p "${RUN_DIR}"
cd "${ROOT_DIR}"

resolve_destination_id() {
  if [ -n "${DESTINATION_ID}" ]; then
    echo "${DESTINATION_ID}"
    return
  fi

  local booted
  booted="$(xcrun simctl list devices booted available | awk -F '[()]' '/iPhone/ {print $2; exit}')"
  if [ -n "${booted}" ]; then
    echo "${booted}"
    return
  fi

  xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 Pro Max/ && /iOS 26/ {print $2; exit}'
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

echo "Running playback QA loop ${LOOPS}x on simulator ${DESTINATION_ID}"
echo "Artifacts: ${RUN_DIR}"

open -a Simulator >/dev/null 2>&1 || true
xcrun simctl boot "${DESTINATION_ID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${DESTINATION_ID}" -b

echo "Starting ReelFin log capture..."
xcrun simctl spawn "${DESTINATION_ID}" log stream \
  --style compact \
  --level info \
  --predicate 'subsystem == "com.reelfin.app" OR process == "ReelFin"' \
  > "${RUN_DIR}/reelfin.log" 2>&1 &
LOG_CAPTURE_PID=$!

LIVE_TEST_ARGS=()
if [ -n "${REELFIN_TEST_SERVER_URL:-}" ] && [ -n "${REELFIN_TEST_USERNAME:-}" ] && [ -n "${REELFIN_TEST_PASSWORD:-}" ]; then
  LIVE_TEST_ARGS+=(
    "-only-testing:PlaybackEngineTests/PlaybackIntegrationProbeTests/testLiveServerPlaybackProbeLoop"
    "-only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testLiveLoginAndStartPlayback"
  )
  echo "Live playback probes: enabled"
else
  echo "Live playback probes: skipped (missing REELFIN_TEST_SERVER_URL / REELFIN_TEST_USERNAME / REELFIN_TEST_PASSWORD)"
fi

for ((i=1; i<=LOOPS; i++)); do
  echo
  echo "=== QA LOOP ${i}/${LOOPS} ==="

  XCODEBUILD_CMD=(
    xcodebuild test
    -project ReelFin.xcodeproj
    -scheme ReelFin
    -destination "id=${DESTINATION_ID}"
    -only-testing:PlaybackEngineTests
    -only-testing:ImageCacheTests
  )

  if [ "${#LIVE_TEST_ARGS[@]}" -gt 0 ]; then
    XCODEBUILD_CMD+=("${LIVE_TEST_ARGS[@]}")
  fi

  "${XCODEBUILD_CMD[@]}" | tee "${RUN_DIR}/xcodebuild-loop-${i}.log"
done

APP_PATH="$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
  -path "*ReelFin*/Build/Products/Debug-iphonesimulator/ReelFin.app" \
  ! -path "*/Index.noindex/*" | head -n 1)"
if [ -n "${APP_PATH}" ]; then
  echo
  echo "Installing app: ${APP_PATH}"
  xcrun simctl install "${DESTINATION_ID}" "${APP_PATH}" || true
  xcrun simctl terminate "${DESTINATION_ID}" com.reelfin.app || true
  xcrun simctl launch "${DESTINATION_ID}" com.reelfin.app >/dev/null 2>&1 || true
fi

echo
echo "QA loop finished."
echo "Logs: ${RUN_DIR}/reelfin.log"
