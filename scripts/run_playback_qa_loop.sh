#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOPS="${1:-3}"
DESTINATION_ID="${2:-1D6F2FC9-3460-4DC8-BC31-33DC75C5AD06}"

if ! [[ "${LOOPS}" =~ ^[0-9]+$ ]] || [ "${LOOPS}" -lt 1 ]; then
  echo "Usage: $0 [loops>=1] [simulator-device-id]"
  exit 1
fi

echo "Running playback QA loop ${LOOPS}x on simulator ${DESTINATION_ID}"
cd "${ROOT_DIR}"

LIVE_TEST_ARGS=()
if [ -n "${REELFIN_TEST_SERVER_URL:-}" ] && [ -n "${REELFIN_TEST_USERNAME:-}" ] && [ -n "${REELFIN_TEST_PASSWORD:-}" ]; then
  LIVE_TEST_ARGS+=("-only-testing:PlaybackEngineTests/PlaybackIntegrationProbeTests/testLiveServerPlaybackProbeLoop")
  echo "Live playback probes: enabled (using REELFIN_TEST_* env vars)"
else
  echo "Live playback probes: skipped (missing REELFIN_TEST_SERVER_URL / USERNAME / PASSWORD)"
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

  "${XCODEBUILD_CMD[@]}"
done

APP_PATH="$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
  -path "*ReelFin*/Build/Products/Debug-iphonesimulator/ReelFin.app" \
  ! -path "*/Index.noindex/*" | head -n 1)"
if [ -n "${APP_PATH}" ]; then
  echo
  echo "Installing app: ${APP_PATH}"
  xcrun simctl install "${DESTINATION_ID}" "${APP_PATH}" || true
  xcrun simctl terminate "${DESTINATION_ID}" com.reelfin.app || true

  launched=0
  for _ in 1 2 3; do
    if xcrun simctl launch "${DESTINATION_ID}" com.reelfin.app; then
      launched=1
      break
    fi
    sleep 1
  done

  if [ "${launched}" -ne 1 ]; then
    echo "Warning: app launch failed after install (simulator state issue)."
  fi
fi

echo
echo "QA loop finished."
