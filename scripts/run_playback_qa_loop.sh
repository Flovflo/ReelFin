#!/usr/bin/env bash
set -euo pipefail
umask 077
set +x

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QA_HOME="${HOME:-/Users/flo}"
PYTHON_RUNNER="${ROOT_DIR}/scripts/run_python_with_uv.sh"
LOOPS="${1:-1}"
DESTINATION_ID="${2:-}"
ARTIFACT_ROOT="${REELFIN_QA_ARTIFACT_ROOT:-${ROOT_DIR}/.artifacts/playback-qa}"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="${ARTIFACT_ROOT}/${TIMESTAMP}-$$"

qa_server_url="${REELFIN_TEST_SERVER_URL:-${JELLYFIN_BASE_URL:-${JELLYFIN_SERVER:-}}}"
qa_username="${REELFIN_TEST_USERNAME:-${JELLYFIN_USERNAME:-${JELLYFIN_USER:-}}}"
qa_password="${REELFIN_TEST_PASSWORD:-${JELLYFIN_PASSWORD:-${JELLYFIN_PASS:-}}}"
unset REELFIN_TEST_SERVER_URL REELFIN_TEST_USERNAME REELFIN_TEST_PASSWORD
unset JELLYFIN_BASE_URL JELLYFIN_USERNAME JELLYFIN_PASSWORD JELLYFIN_SERVER JELLYFIN_USER JELLYFIN_PASS
unset SIMCTL_CHILD_REELFIN_TEST_SERVER_URL SIMCTL_CHILD_REELFIN_TEST_USERNAME SIMCTL_CHILD_REELFIN_TEST_PASSWORD

TRANSIENT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/reelfin-playback-qa.XXXXXX")"
chmod 700 "${TRANSIENT_ROOT}"
DERIVED_DATA_PATH="${TRANSIENT_ROOT}/xcode-derived-data"
LOG_CAPTURE_PID=""
CLEANUP_STARTED=0
ARTIFACT_SCAN_COMPLETE=0
RUNTIME_STATUS_FILE="${TRANSIENT_ROOT}/runtime-pipeline.status"
RUNTIME_PRODUCER_PID_FILE="${TRANSIENT_ROOT}/runtime-producer.pid"
RUNTIME_STOP_REQUESTED="${TRANSIENT_ROOT}/runtime-stop-requested"
RUNTIME_FIFO="${TRANSIENT_ROOT}/runtime-stream.fifo"

redact_stream() {
  env -i \
    PATH="${PATH}" \
    HOME="${QA_HOME}" \
    UV_PYTHON_INSTALL_DIR="/Users/flo/.local/share/reelfin-codex/uv/python" \
    UV_CACHE_DIR="/Users/flo/.cache/reelfin-codex/uv" \
    PYTHONDONTWRITEBYTECODE=1 \
    REELFIN_TEST_SERVER_URL="${qa_server_url}" \
    REELFIN_TEST_USERNAME="${qa_username}" \
    REELFIN_TEST_PASSWORD="${qa_password}" \
    "${PYTHON_RUNNER}" scripts/redact_xctest_activity.py
}

scan_artifacts() {
  [[ ! -d "${RUN_DIR}" ]] && return 0
  printf '%s\n%s\n%s\n' "${qa_server_url}" "${qa_username}" "${qa_password}" \
    | env -i \
      PATH="${PATH}" \
      HOME="${QA_HOME}" \
      UV_PYTHON_INSTALL_DIR="/Users/flo/.local/share/reelfin-codex/uv/python" \
      UV_CACHE_DIR="/Users/flo/.cache/reelfin-codex/uv" \
      PYTHONDONTWRITEBYTECODE=1 \
      "${PYTHON_RUNNER}" scripts/assert_no_secret_artifacts.py "${RUN_DIR}" --secrets-stdin
}

stop_runtime_capture() {
  local capture_pid="${LOG_CAPTURE_PID}"
  local producer_pid=""
  LOG_CAPTURE_PID=""
  if [[ -n "${capture_pid}" ]]; then
    : > "${RUNTIME_STOP_REQUESTED}"
    for _ in {1..100}; do
      [[ -s "${RUNTIME_PRODUCER_PID_FILE}" || -f "${RUNTIME_STATUS_FILE}" ]] && break
      kill -0 "${capture_pid}" 2>/dev/null || break
      sleep 0.01
    done
    if [[ -s "${RUNTIME_PRODUCER_PID_FILE}" ]]; then
      IFS= read -r producer_pid < "${RUNTIME_PRODUCER_PID_FILE}" || true
      [[ "${producer_pid}" =~ ^[0-9]+$ ]] && kill "${producer_pid}" 2>/dev/null || true
    fi
    wait "${capture_pid}" 2>/dev/null || true
  fi
  [[ -f "${RUNTIME_STATUS_FILE}" ]] || {
    [[ -z "${capture_pid}" ]] && return 0
    echo "Runtime capture ended without pipeline status." >&2
    return 70
  }
  local producer_status redactor_status tee_status pipeline_component_status
  IFS=' ' read -r producer_status redactor_status tee_status < "${RUNTIME_STATUS_FILE}" || return 70
  rm -f "${RUNTIME_STATUS_FILE}"
  for pipeline_component_status in "${producer_status}" "${redactor_status}" "${tee_status}"; do
    [[ "${pipeline_component_status}" =~ ^[0-9]+$ ]] || return 70
    [[ "${pipeline_component_status}" -eq 0 ]] || return "${pipeline_component_status}"
  done
  return 0
}

cleanup() {
  local status="${1:-1}"
  [[ "${CLEANUP_STARTED}" -eq 1 ]] && exit "${status}"
  CLEANUP_STARTED=1
  set +e
  stop_runtime_capture
  local runtime_status="$?"
  [[ "${status}" -ne 0 || "${runtime_status}" -eq 0 ]] || status="${runtime_status}"
  if [[ "${ARTIFACT_SCAN_COMPLETE}" -ne 1 ]] && ! scan_artifacts; then
    rm -rf "${RUN_DIR}" 2>/dev/null || true
    status=1
  fi
  rm -rf "${TRANSIENT_ROOT}" 2>/dev/null || true
  qa_server_url=""
  qa_username=""
  qa_password=""
  exit "${status}"
}
trap 'cleanup "$?"' EXIT HUP INT TERM

run_logged() {
  local output_file="$1"
  shift
  set +e
  "$@" 2>&1 | redact_stream | tee "${output_file}"
  local producer_status="${PIPESTATUS[0]}" redactor_status="${PIPESTATUS[1]}" tee_status="${PIPESTATUS[2]}"
  set -e
  [[ "${producer_status}" -eq 0 ]] || return "${producer_status}"
  [[ "${redactor_status}" -eq 0 ]] || return "${redactor_status}"
  [[ "${tee_status}" -eq 0 ]] || return "${tee_status}"
}

runtime_log_capture() {
  local output_file="$1"
  local producer_pid producer_status redactor_status tee_status
  local -a pipeline_statuses
  rm -f "${RUNTIME_STATUS_FILE}" "${RUNTIME_PRODUCER_PID_FILE}" "${RUNTIME_STOP_REQUESTED}" "${RUNTIME_FIFO}"
  mkfifo "${RUNTIME_FIFO}"
  set +e
  xcrun simctl spawn "${DESTINATION_ID}" log stream \
    --style compact \
    --level info \
    --predicate 'subsystem == "com.reelfin.app" OR process == "ReelFin"' \
    > "${RUNTIME_FIFO}" 2>&1 &
  producer_pid=$!
  printf '%s\n' "${producer_pid}" > "${RUNTIME_PRODUCER_PID_FILE}"
  redact_stream < "${RUNTIME_FIFO}" | tee "${output_file}" >/dev/null
  pipeline_statuses=("${PIPESTATUS[@]}")
  redactor_status="${pipeline_statuses[0]}"
  tee_status="${pipeline_statuses[1]}"
  wait "${producer_pid}"
  producer_status="$?"
  if [[ -f "${RUNTIME_STOP_REQUESTED}" && ( "${producer_status}" -eq 130 || "${producer_status}" -eq 143 ) ]]; then
    producer_status=0
  fi
  printf '%s %s %s\n' "${producer_status}" "${redactor_status}" "${tee_status}" > "${RUNTIME_STATUS_FILE}.tmp"
  mv "${RUNTIME_STATUS_FILE}.tmp" "${RUNTIME_STATUS_FILE}"
  rm -f "${RUNTIME_PRODUCER_PID_FILE}" "${RUNTIME_STOP_REQUESTED}" "${RUNTIME_FIFO}"
  return 0
}

if ! [[ "${LOOPS}" =~ ^[0-9]+$ ]] || [[ "${LOOPS}" -lt 1 ]]; then
  echo "Usage: $0 [loops>=1] [simulator-device-id]"
  exit 1
fi

mkdir -p -m 700 "${RUN_DIR}" "${DERIVED_DATA_PATH}"
cd "${ROOT_DIR}"

resolve_destination_id() {
  if [[ -n "${DESTINATION_ID}" ]]; then
    printf '%s\n' "${DESTINATION_ID}"
    return
  fi
  local booted
  booted="$(xcrun simctl list devices booted available | awk -F '[()]' '/iPhone/ {print $2; exit}')"
  if [[ -n "${booted}" ]]; then
    printf '%s\n' "${booted}"
    return
  fi
  xcrun simctl list devices available | awk -F '[()]' '/iPhone 17 \(.*26\.5/ {print $2; exit} /iPhone 17/ {fallback=$2} END {if (fallback) print fallback}'
}

DESTINATION_ID="$(resolve_destination_id)"
if [[ -z "${DESTINATION_ID}" ]]; then
  echo "No usable iPhone 17 simulator found."
  exit 1
fi

echo "Running playback QA loop ${LOOPS}x on simulator ${DESTINATION_ID}"
echo "Artifacts: ${RUN_DIR}"

open -a Simulator >/dev/null 2>&1 || true
xcrun simctl boot "${DESTINATION_ID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${DESTINATION_ID}" -b

echo "Starting redacted ReelFin runtime capture..."
runtime_log_capture "${RUN_DIR}/reelfin.log" &
LOG_CAPTURE_PID=$!

LIVE_TEST_ARGS=()
if [[ -n "${qa_server_url}" && -n "${qa_username}" && -n "${qa_password}" ]]; then
  LIVE_TEST_ARGS+=(
    "-only-testing:PlaybackEngineTests/PlaybackIntegrationProbeTests/testLiveServerPlaybackProbeLoop"
    "-only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testLiveLoginAndStartPlayback"
  )
  echo "Live playback probes: enabled"
else
  echo "Live playback probes: skipped (missing ephemeral credentials)"
fi

credentialed_env=(
  env -i
  PATH="${PATH}"
  HOME="${QA_HOME}"
  TMPDIR="${TRANSIENT_ROOT}"
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
  REELFIN_TEST_SERVER_URL="${qa_server_url}"
  REELFIN_TEST_USERNAME="${qa_username}"
  REELFIN_TEST_PASSWORD="${qa_password}"
  SIMCTL_CHILD_REELFIN_TEST_SERVER_URL="${qa_server_url}"
  SIMCTL_CHILD_REELFIN_TEST_USERNAME="${qa_username}"
  SIMCTL_CHILD_REELFIN_TEST_PASSWORD="${qa_password}"
)

for ((i=1; i<=LOOPS; i++)); do
  echo
  echo "=== QA LOOP ${i}/${LOOPS} ==="
  XCODEBUILD_CMD=(
    xcodebuild test
    -project ReelFin.xcodeproj
    -scheme ReelFin
    -destination "id=${DESTINATION_ID}"
    -derivedDataPath "${DERIVED_DATA_PATH}"
    -only-testing:PlaybackEngineTests
    -only-testing:ImageCacheTests
  )
  if [[ "${#LIVE_TEST_ARGS[@]}" -gt 0 ]]; then
    XCODEBUILD_CMD+=("${LIVE_TEST_ARGS[@]}")
  fi
  run_logged "${RUN_DIR}/xcodebuild-loop-${i}.log" "${credentialed_env[@]}" "${XCODEBUILD_CMD[@]}"
done

APP_PATH="$(find "${DERIVED_DATA_PATH}" -path '*/Build/Products/Debug-iphonesimulator/ReelFin.app' ! -path '*/Index.noindex/*' | head -n 1)"
if [[ -n "${APP_PATH}" ]]; then
  echo
  echo "Installing freshly built app."
  xcrun simctl install "${DESTINATION_ID}" "${APP_PATH}" || true
  xcrun simctl terminate "${DESTINATION_ID}" com.reelfin.app || true
  xcrun simctl launch "${DESTINATION_ID}" com.reelfin.app >/dev/null 2>&1 || true
fi

stop_runtime_capture
scan_artifacts
ARTIFACT_SCAN_COMPLETE=1

echo
echo "QA loop finished."
echo "Logs: ${RUN_DIR}/reelfin.log"
