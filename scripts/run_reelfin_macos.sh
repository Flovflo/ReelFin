#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${REELFIN_MACOS_DERIVED_DATA_PATH:-${ROOT_DIR}/.artifacts/macos/DerivedData}"
DESTINATION="${REELFIN_MACOS_DESTINATION:-platform=macOS,arch=arm64,variant=Mac Catalyst}"
LOG_DIR="${REELFIN_MACOS_LOG_DIR:-${ROOT_DIR}/.artifacts/macos}"
APP_NAME="ReelFin"
RUN_LOGS=0
VERIFY=0

usage() {
  cat <<USAGE
Usage: $0 [--verify] [--logs]

Builds and launches ReelFin as a Mac Catalyst app.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify)
      VERIFY=1
      shift
      ;;
    --logs)
      RUN_LOGS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

mkdir -p "${LOG_DIR}"
cd "${ROOT_DIR}"

pkill -x "${APP_NAME}" >/dev/null 2>&1 || true

xcodegen generate

xcodebuild build \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  | tee "${LOG_DIR}/xcodebuild-macos.log"

APP_PATH="$(find "${DERIVED_DATA_PATH}/Build/Products" -path "*/Debug-maccatalyst/${APP_NAME}.app" -print -quit)"
if [[ -z "${APP_PATH}" ]]; then
  echo "Unable to locate built app under ${DERIVED_DATA_PATH}/Build/Products"
  exit 1
fi

/usr/bin/open -n "${APP_PATH}"

if [[ "${VERIFY}" -eq 1 ]]; then
  for _ in {1..30}; do
    if pgrep -x "${APP_NAME}" >/dev/null; then
      echo "${APP_NAME}=RUNNING"
      break
    fi
    sleep 1
  done

  if ! pgrep -x "${APP_NAME}" >/dev/null; then
    echo "${APP_NAME}=NOT_RUNNING"
    exit 1
  fi
fi

if [[ "${RUN_LOGS}" -eq 1 ]]; then
  /usr/bin/log stream \
    --style compact \
    --level debug \
    --predicate "process == \"${APP_NAME}\""
fi
