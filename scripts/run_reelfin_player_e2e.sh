#!/usr/bin/env bash
set -euo pipefail
umask 077
set +x

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QA_HOME="${HOME:-/Users/flo}"
ENV_FILE="${REELFIN_E2E_ENV_FILE:-${ROOT_DIR}/.artifacts/secrets/reelfin-e2e.env}"
ARTIFACT_ROOT="${REELFIN_QA_ARTIFACT_ROOT:-${ROOT_DIR}/.artifacts/player-e2e}"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="${ARTIFACT_ROOT}/${TIMESTAMP}-$$"
TRANSIENT_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/reelfin-player-qa.XXXXXX")"
chmod 700 "${TRANSIENT_ROOT}"
LIVE_UI_TARGET_ENV="${TRANSIENT_ROOT}/live-ui-target.env"
DERIVED_DATA_PATH="${TRANSIENT_ROOT}/xcode-derived-data-ios"
TVOS_DERIVED_DATA_PATH="${TRANSIENT_ROOT}/xcode-derived-data-tvos"
IOS_DESTINATION="${REELFIN_E2E_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
TVOS_DESTINATION="${REELFIN_E2E_TVOS_DESTINATION:-platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.5}"
LOOPS="${REELFIN_TEST_LOOPS:-2}"
SAMPLE_SIZE="${REELFIN_TEST_SAMPLE_SIZE:-8}"
MAX_FAILURES="${REELFIN_TEST_MAX_FAILURES:-0}"
RUN_UI=1
RUN_TVOS=1
PASSWORD_STDIN=0
PYTHON_RUNNER="${ROOT_DIR}/scripts/run_python_with_uv.sh"
UI_LOG_PID=""
CLEANUP_STARTED=0
ARTIFACT_SCAN_COMPLETE=0
UI_RUNTIME_STATUS_FILE="${TRANSIENT_ROOT}/ui-runtime-pipeline.status"
UI_RUNTIME_PRODUCER_PID_FILE="${TRANSIENT_ROOT}/ui-runtime-producer.pid"
UI_RUNTIME_STOP_REQUESTED="${TRANSIENT_ROOT}/ui-runtime-stop-requested"
UI_RUNTIME_FIFO="${TRANSIENT_ROOT}/ui-runtime-stream.fifo"

qa_server_url="${REELFIN_TEST_SERVER_URL:-${JELLYFIN_BASE_URL:-${JELLYFIN_SERVER:-}}}"
qa_username="${REELFIN_TEST_USERNAME:-${JELLYFIN_USERNAME:-${JELLYFIN_USER:-}}}"
qa_password="${REELFIN_TEST_PASSWORD:-${JELLYFIN_PASSWORD:-${JELLYFIN_PASS:-}}}"
qa_directplay_item_id="${TEST_DIRECTPLAY_MP4_ITEM_ID:-}"
qa_mkv_item_id="${TEST_MKV_ITEM_ID:-${TEST_MKV_DOLBY_VISION_ITEM_ID:-}}"
qa_dv_item_id="${TEST_DOLBY_VISION_ITEM_ID:-${TEST_DIRECTPLAY_DOLBY_VISION_ITEM_ID:-${TEST_MKV_DOLBY_VISION_ITEM_ID:-}}}"
qa_hdr_item_id="${TEST_HDR_ITEM_ID:-${qa_dv_item_id}}"

unset REELFIN_TEST_SERVER_URL REELFIN_TEST_USERNAME REELFIN_TEST_PASSWORD
unset JELLYFIN_BASE_URL JELLYFIN_USERNAME JELLYFIN_PASSWORD JELLYFIN_SERVER JELLYFIN_USER JELLYFIN_PASS
unset SIMCTL_CHILD_REELFIN_TEST_SERVER_URL SIMCTL_CHILD_REELFIN_TEST_USERNAME SIMCTL_CHILD_REELFIN_TEST_PASSWORD
unset TEST_DIRECTPLAY_MP4_ITEM_ID TEST_MKV_ITEM_ID TEST_MKV_DOLBY_VISION_ITEM_ID
unset TEST_DOLBY_VISION_ITEM_ID TEST_DIRECTPLAY_DOLBY_VISION_ITEM_ID TEST_HDR_ITEM_ID

cleanup() {
  local status="${1:-1}"
  local runtime_status=0
  [[ "${CLEANUP_STARTED}" -eq 1 ]] && exit "${status}"
  CLEANUP_STARTED=1
  set +e
  if declare -F stop_ios_runtime_log_capture >/dev/null; then
    stop_ios_runtime_log_capture "${UI_LOG_PID}"
    runtime_status="$?"
    [[ "${status}" -ne 0 || "${runtime_status}" -eq 0 ]] || status="${runtime_status}"
  fi
  rm -f "${LIVE_UI_TARGET_ENV}" >/dev/null 2>&1
  if [[ "${ARTIFACT_SCAN_COMPLETE}" -ne 1 ]] && declare -F scan_retained_artifacts >/dev/null && ! scan_retained_artifacts; then
    rm -rf "${RUN_DIR}" >/dev/null 2>&1
    status=1
  elif [[ "${ARTIFACT_SCAN_COMPLETE}" -ne 1 ]] && ! declare -F scan_retained_artifacts >/dev/null; then
    rm -rf "${RUN_DIR}" >/dev/null 2>&1
  fi
  rm -rf "${TRANSIENT_ROOT}" >/dev/null 2>&1
  qa_server_url=""
  qa_username=""
  qa_password=""
  qa_directplay_item_id=""
  qa_mkv_item_id=""
  qa_dv_item_id=""
  qa_hdr_item_id=""
  exit "${status}"
}
trap 'cleanup "$?"' EXIT HUP INT TERM

usage() {
  cat <<USAGE
Usage: $0 [--env-file nonsecret.env] [--password-stdin] [--loops n] [--sample-size n] [--max-failures n] [--skip-ui] [--skip-tvos]

Runs ReelFin player validation without printing secrets:
  1. explicit Jellyfin item probes from TEST_*_ITEM_ID
  2. live original-stream range/seek benchmark
  3. live Jellyfin playback probe loop
  4. deterministic PlaybackEngine/native player tests
  5. optional iOS live UI smoke test
  6. optional tvOS simulator build gate
  7. runtime log cleanliness and deep playback evidence gates
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      [[ $# -ge 2 ]] || { echo "--env-file requires a path"; exit 2; }
      ENV_FILE="$2"
      shift 2
      ;;
    --password-stdin)
      PASSWORD_STDIN=1
      shift
      ;;
    --loops)
      LOOPS="$2"
      shift 2
      ;;
    --sample-size)
      SAMPLE_SIZE="$2"
      shift 2
      ;;
    --max-failures)
      MAX_FAILURES="$2"
      shift 2
      ;;
    --skip-ui)
      RUN_UI=0
      shift
      ;;
    --skip-tvos)
      RUN_TVOS=0
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

mkdir -p -m 700 "${RUN_DIR}" "${DERIVED_DATA_PATH}" "${TVOS_DERIVED_DATA_PATH}"
cd "${ROOT_DIR}"

load_env_file() {
  local line key value line_number=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    if [[ "${line}" != *=* ]]; then
      echo "Invalid env line ${line_number}: missing '='"
      return 2
    fi
    key="${line%%=*}"
    value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "Invalid env line ${line_number}: invalid key"
      return 2
    fi
    if [[ "${key}" =~ (PASSWORD|PASS|TOKEN|API_KEY|SECRET|SERVER|URL|USERNAME|USER) ]]; then
      echo "Credential keys are rejected in env files; use the ephemeral process environment or password stdin."
      return 2
    fi
    if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    case "${key}" in
      TEST_DIRECTPLAY_MP4_ITEM_ID) qa_directplay_item_id="${value}" ;;
      TEST_MKV_ITEM_ID|TEST_MKV_DOLBY_VISION_ITEM_ID) qa_mkv_item_id="${value}" ;;
      TEST_DOLBY_VISION_ITEM_ID|TEST_DIRECTPLAY_DOLBY_VISION_ITEM_ID) qa_dv_item_id="${value}" ;;
      TEST_HDR_ITEM_ID) qa_hdr_item_id="${value}" ;;
      *) echo "Unsupported nonsecret env key at line ${line_number}."; return 2 ;;
    esac
  done < "${ENV_FILE}"
}

if [[ -f "${ENV_FILE}" ]]; then
  load_env_file
fi

if [[ "${PASSWORD_STDIN}" -eq 1 ]]; then
  IFS= read -r -s qa_password || true
  [[ -t 0 ]] && printf '\n'
fi

qa_hdr_item_id="${qa_hdr_item_id:-${qa_dv_item_id}}"
qa_explicit_only="${REELFIN_TEST_EXPLICIT_ONLY:-1}"
qa_directplay_only="${REELFIN_TEST_DIRECTPLAY_ONLY:-1}"
qa_ui_smoke_seconds="${REELFIN_LIVE_UI_SMOKE_OBSERVE_SECONDS:-45}"
qa_ui_long_seconds="${REELFIN_LIVE_UI_LONG_OBSERVE_SECONDS:-120}"
qa_deep_directplay_seconds="${REELFIN_DEEP_DIRECTPLAY_LONG_MIN_SECONDS:-75}"
qa_deep_evidence="${REELFIN_PLAYER_DEEP_EVIDENCE:-1}"
qa_deep_min_seconds="${REELFIN_DEEP_PLAYBACK_MIN_SECONDS:-20}"
qa_deep_min_ticks="${REELFIN_DEEP_PLAYBACK_MIN_TICKS:-3}"
unset REELFIN_TEST_EXPLICIT_ONLY REELFIN_TEST_DIRECTPLAY_ONLY
unset REELFIN_LIVE_UI_SMOKE_OBSERVE_SECONDS REELFIN_LIVE_UI_LONG_OBSERVE_SECONDS
unset REELFIN_DEEP_DIRECTPLAY_LONG_MIN_SECONDS REELFIN_PLAYER_DEEP_EVIDENCE
unset REELFIN_DEEP_PLAYBACK_MIN_SECONDS REELFIN_DEEP_PLAYBACK_MIN_TICKS

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "${value}" || "${value}" == "..." ]]; then
    echo "${name}=MISSING_OR_PLACEHOLDER"
    return 1
  fi
  echo "${name}=SET"
}

redact_xcode_ui_log() {
  env -i \
    PATH="${PATH}" \
    HOME="${QA_HOME}" \
    UV_PYTHON_INSTALL_DIR="/Users/flo/.local/share/reelfin-codex/uv/python" \
    UV_CACHE_DIR="/Users/flo/.cache/reelfin-codex/uv" \
    PYTHONDONTWRITEBYTECODE=1 \
    REELFIN_TEST_SERVER_URL="${qa_server_url}" \
    REELFIN_TEST_USERNAME="${qa_username}" \
    REELFIN_TEST_PASSWORD="${qa_password}" \
    TEST_DIRECTPLAY_MP4_ITEM_ID="${qa_directplay_item_id}" \
    TEST_MKV_ITEM_ID="${qa_mkv_item_id}" \
    TEST_HDR_ITEM_ID="${qa_hdr_item_id}" \
    TEST_DOLBY_VISION_ITEM_ID="${qa_dv_item_id}" \
    "${PYTHON_RUNNER}" scripts/redact_xctest_activity.py
}

scan_retained_artifacts() {
  [[ ! -d "${RUN_DIR}" ]] && return 0
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' \
    "${qa_server_url}" "${qa_username}" "${qa_password}" \
    "${qa_directplay_item_id}" "${qa_mkv_item_id}" "${qa_hdr_item_id}" "${qa_dv_item_id}" \
    | env -i \
      PATH="${PATH}" \
      HOME="${QA_HOME}" \
      UV_PYTHON_INSTALL_DIR="/Users/flo/.local/share/reelfin-codex/uv/python" \
      UV_CACHE_DIR="/Users/flo/.cache/reelfin-codex/uv" \
      PYTHONDONTWRITEBYTECODE=1 \
      "${PYTHON_RUNNER}" scripts/assert_no_secret_artifacts.py "${RUN_DIR}" --secrets-stdin
}

run_logged() {
  local output_file="$1"
  shift
  set +e
  "$@" 2>&1 | redact_xcode_ui_log | tee "${output_file}"
  local producer_status="${PIPESTATUS[0]}" redactor_status="${PIPESTATUS[1]}" tee_status="${PIPESTATUS[2]}"
  set -e
  [[ "${producer_status}" -eq 0 ]] || return "${producer_status}"
  [[ "${redactor_status}" -eq 0 ]] || return "${redactor_status}"
  [[ "${tee_status}" -eq 0 ]] || return "${tee_status}"
}

run_logged_append() {
  local output_file="$1"
  shift
  set +e
  "$@" 2>&1 | redact_xcode_ui_log | tee -a "${output_file}"
  local producer_status="${PIPESTATUS[0]}" redactor_status="${PIPESTATUS[1]}" tee_status="${PIPESTATUS[2]}"
  set -e
  [[ "${producer_status}" -eq 0 ]] || return "${producer_status}"
  [[ "${redactor_status}" -eq 0 ]] || return "${redactor_status}"
  [[ "${tee_status}" -eq 0 ]] || return "${tee_status}"
}

base_child_env=(
  env -i
  PATH="${PATH}"
  HOME="${QA_HOME}"
  TMPDIR="${TRANSIENT_ROOT}"
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
  UV_PYTHON_INSTALL_DIR="/Users/flo/.local/share/reelfin-codex/uv/python"
  UV_CACHE_DIR="/Users/flo/.cache/reelfin-codex/uv"
  PYTHONDONTWRITEBYTECODE=1
)

ios_simulator_name() {
  sed -E 's/.*(^|,)name=([^,]+).*/\2/' <<< "${IOS_DESTINATION}"
}

ios_simulator_device() {
  local simulator_name
  simulator_name="$(ios_simulator_name)"
  xcrun simctl list devices -j | SIM_NAME="${simulator_name}" "${PYTHON_RUNNER}" -c '
import json
import os
import sys

name = os.environ["SIM_NAME"]
data = json.load(sys.stdin)
fallback = None
for devices in data.get("devices", {}).values():
    for device in devices:
        if device.get("name") != name or not device.get("isAvailable", True):
            continue
        if device.get("state") == "Booted":
            print(device["udid"])
            raise SystemExit(0)
        fallback = fallback or device.get("udid")
if fallback:
    print(fallback)
    raise SystemExit(0)
raise SystemExit(f"Simulator not found: {name}")
'
}

ensure_ios_simulator_booted_for_logs() {
  local simulator_name
  simulator_name="$(ios_simulator_name)"
  xcrun simctl boot "${simulator_name}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$(ios_simulator_device)" -b >/dev/null
}

settle_ios_simulator_for_ui_test() {
  ensure_ios_simulator_booted_for_logs
  local simulator_device
  simulator_device="$(ios_simulator_device)"
  xcrun simctl terminate "${simulator_device}" com.reelfin.app >/dev/null 2>&1 || true
  xcrun simctl terminate "${simulator_device}" com.reelfin.ui.tests.xctrunner >/dev/null 2>&1 || true
  sleep 2
}

reset_ios_app_data_for_live_ui_test() {
  ensure_ios_simulator_booted_for_logs
  local simulator_device
  simulator_device="$(ios_simulator_device)"
  xcrun simctl terminate "${simulator_device}" com.reelfin.app >/dev/null 2>&1 || true
  xcrun simctl uninstall "${simulator_device}" com.reelfin.app >/dev/null 2>&1 || true
}

start_ios_runtime_log_capture() {
  local output_file="$1"
  local simulator_device
  simulator_device="$(ios_simulator_device)"
  rm -f "${UI_RUNTIME_STATUS_FILE}" "${UI_RUNTIME_PRODUCER_PID_FILE}" \
    "${UI_RUNTIME_STOP_REQUESTED}" "${UI_RUNTIME_FIFO}"
  mkfifo "${UI_RUNTIME_FIFO}"
  (
    local producer_pid producer_status redactor_status tee_status
    local -a pipeline_statuses
    set +e
    xcrun simctl spawn "${simulator_device}" log stream \
      --style compact \
      --level debug \
      --predicate 'subsystem == "com.reelfin.app" OR process == "ReelFin" OR process == "ReelFinUITests-Runner"' \
      > "${UI_RUNTIME_FIFO}" 2>&1 &
    producer_pid=$!
    printf '%s\n' "${producer_pid}" > "${UI_RUNTIME_PRODUCER_PID_FILE}"
    redact_xcode_ui_log < "${UI_RUNTIME_FIFO}" | tee "${output_file}" >/dev/null
    pipeline_statuses=("${PIPESTATUS[@]}")
    redactor_status="${pipeline_statuses[0]}"
    tee_status="${pipeline_statuses[1]}"
    wait "${producer_pid}"
    producer_status="$?"
    if [[ -f "${UI_RUNTIME_STOP_REQUESTED}" && ( "${producer_status}" -eq 130 || "${producer_status}" -eq 143 ) ]]; then
      producer_status=0
    fi
    printf '%s %s %s\n' "${producer_status}" "${redactor_status}" "${tee_status}" > "${UI_RUNTIME_STATUS_FILE}.tmp"
    mv "${UI_RUNTIME_STATUS_FILE}.tmp" "${UI_RUNTIME_STATUS_FILE}"
    rm -f "${UI_RUNTIME_PRODUCER_PID_FILE}" "${UI_RUNTIME_STOP_REQUESTED}" "${UI_RUNTIME_FIFO}"
    return 0
  ) &
  UI_LOG_PID=$!
}

stop_ios_runtime_log_capture() {
  local pid="${1:-}"
  [[ -z "${pid}" ]] && return 0
  local producer_pid=""
  : > "${UI_RUNTIME_STOP_REQUESTED}"
  for _ in {1..100}; do
    [[ -s "${UI_RUNTIME_PRODUCER_PID_FILE}" || -f "${UI_RUNTIME_STATUS_FILE}" ]] && break
    kill -0 "${pid}" 2>/dev/null || break
    sleep 0.01
  done
  if [[ -s "${UI_RUNTIME_PRODUCER_PID_FILE}" ]]; then
    IFS= read -r producer_pid < "${UI_RUNTIME_PRODUCER_PID_FILE}" || true
    [[ "${producer_pid}" =~ ^[0-9]+$ ]] && kill "${producer_pid}" >/dev/null 2>&1 || true
  fi
  wait "${pid}" >/dev/null 2>&1 || true
  [[ -f "${UI_RUNTIME_STATUS_FILE}" ]] || {
    echo "Runtime capture ended without pipeline status." >&2
    return 70
  }
  local producer_status redactor_status tee_status pipeline_component_status
  IFS=' ' read -r producer_status redactor_status tee_status < "${UI_RUNTIME_STATUS_FILE}" || return 70
  rm -f "${UI_RUNTIME_STATUS_FILE}"
  for pipeline_component_status in "${producer_status}" "${redactor_status}" "${tee_status}"; do
    [[ "${pipeline_component_status}" =~ ^[0-9]+$ ]] || return 70
    [[ "${pipeline_component_status}" -eq 0 ]] || return "${pipeline_component_status}"
  done
  return 0
}

collect_ios_deep_evidence_file() {
  local output_file="$1"
  local simulator_device
  simulator_device="$(ios_simulator_device)"
  local container_path
  container_path="$(xcrun simctl get_app_container "${simulator_device}" com.reelfin.app data 2>/dev/null || true)"
  if [[ -z "${container_path}" ]]; then
    echo "WARN player deep evidence container unavailable" >> "${output_file}"
    return 0
  fi

  local evidence_file="${container_path}/Library/Caches/ReelFin/Diagnostics/reelfin-player-deep-evidence.jsonl"
  if [[ ! -f "${evidence_file}" ]]; then
    echo "WARN player deep evidence file missing" >> "${output_file}"
    return 0
  fi

  printf '\n----- player deep evidence file -----\n' >> "${output_file}"
  run_logged_append "${output_file}" cat "${evidence_file}"
}

restore_live_ui_target_resume() {
  local state_file="$1"
  local log_file="$2"
  shift 2
  if [[ ! -f "${state_file}" ]]; then
    return 0
  fi
  if ! run_logged_append "${log_file}" "$@" "${PYTHON_RUNNER}" scripts/live_ui_resume_target.py restore --state-file "${state_file}"; then
    printf 'WARN live UI resume restore failed.\n' >> "${log_file}"
  fi
}

run_live_ui_gate() {
  local label="$1"
  local log_suffix="$2"
  local result_name="$3"
  local expect_custom_controls="${4:-0}"
  local open_target_directly="${5:-0}"
  local observe_seconds="${6:-${qa_ui_smoke_seconds}}"
  local ui_runtime_log="${RUN_DIR}/ios-live-ui${log_suffix}-runtime.stream"
  local ui_xcode_log="${RUN_DIR}/xcodebuild-live-ui${log_suffix}.log"
  local ui_resume_log="${RUN_DIR}/live-ui${log_suffix}-resume-target.log"
  local ui_resume_state="${TRANSIENT_ROOT}/live-ui${log_suffix}-resume-target.json"
  local -a ui_resume_env=(
    "${base_child_env[@]}"
    JELLYFIN_BASE_URL="${qa_server_url}"
    JELLYFIN_USERNAME="${qa_username}"
    JELLYFIN_PASSWORD="${qa_password}"
  )
  case "${label}" in
    directplay-mp4) ui_resume_env+=(TEST_DIRECTPLAY_MP4_ITEM_ID="${qa_directplay_item_id}") ;;
    directplay-hdr-dv-long) ui_resume_env+=(TEST_DOLBY_VISION_ITEM_ID="${qa_dv_item_id}") ;;
    samplebuffer-mkv) ui_resume_env+=(TEST_MKV_ITEM_ID="${qa_mkv_item_id}") ;;
  esac
  local -a ui_xcode_env=(
    "${base_child_env[@]}"
    REELFIN_TEST_SERVER_URL="${qa_server_url}"
    REELFIN_TEST_USERNAME="${qa_username}"
    REELFIN_TEST_PASSWORD="${qa_password}"
    SIMCTL_CHILD_REELFIN_TEST_SERVER_URL="${qa_server_url}"
    SIMCTL_CHILD_REELFIN_TEST_USERNAME="${qa_username}"
    SIMCTL_CHILD_REELFIN_TEST_PASSWORD="${qa_password}"
  )

  echo "Running live iOS UI smoke test (${label}, observe=${observe_seconds}s)..."
  run_logged "${ui_resume_log}" "${ui_resume_env[@]}" "${PYTHON_RUNNER}" scripts/live_ui_resume_target.py prepare \
    --scenario "${label}" --state-file "${ui_resume_state}"
  settle_ios_simulator_for_ui_test
  reset_ios_app_data_for_live_ui_test
  start_ios_runtime_log_capture "${ui_runtime_log}"
  set +e
  run_logged "${ui_xcode_log}" "${ui_xcode_env[@]}" \
    REELFIN_LIVE_UI_TARGET_SCENARIO="${label}" \
    REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS="${expect_custom_controls}" \
    REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY="${open_target_directly}" \
    REELFIN_LIVE_UI_OBSERVE_SECONDS="${observe_seconds}" \
    REELFIN_PLAYER_DEEP_EVIDENCE="${qa_deep_evidence}" \
    REELFIN_PLAYER_DEEP_EVIDENCE_RESET=1 \
    SIMCTL_CHILD_REELFIN_LIVE_UI_TARGET_SCENARIO="${label}" \
    SIMCTL_CHILD_REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS="${expect_custom_controls}" \
    SIMCTL_CHILD_REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY="${open_target_directly}" \
    SIMCTL_CHILD_REELFIN_LIVE_UI_OBSERVE_SECONDS="${observe_seconds}" \
    SIMCTL_CHILD_REELFIN_PLAYER_DEEP_EVIDENCE="${qa_deep_evidence}" \
    SIMCTL_CHILD_REELFIN_PLAYER_DEEP_EVIDENCE_RESET=1 \
    xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination "${IOS_DESTINATION}" \
      -derivedDataPath "${DERIVED_DATA_PATH}" \
      -only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testLiveLoginAndStartPlayback
  ui_status="$?"
  set -e
  if [[ "${ui_status}" -ne 0 ]]; then
    if grep -Eq 'Application failed preflight checks|reason: Busy|Simulator device failed to launch' "${ui_xcode_log}"; then
      echo "Retrying live iOS UI smoke test (${label}) after simulator busy preflight..."
      settle_ios_simulator_for_ui_test
      set +e
      run_logged "${RUN_DIR}/xcodebuild-live-ui${log_suffix}-retry.log" "${ui_xcode_env[@]}" \
        REELFIN_LIVE_UI_TARGET_SCENARIO="${label}" \
        SIMCTL_CHILD_REELFIN_LIVE_UI_TARGET_SCENARIO="${label}" \
        xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination "${IOS_DESTINATION}" \
          -derivedDataPath "${DERIVED_DATA_PATH}" \
          -only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testLiveLoginAndStartPlayback
      retry_status="$?"
      set -e
      if [[ "${retry_status}" -ne 0 ]]; then
        restore_live_ui_target_resume "${ui_resume_state}" "${ui_resume_log}" "${ui_resume_env[@]}"
        stop_ios_runtime_log_capture "${UI_LOG_PID}"
        exit "${retry_status}"
      fi
    else
      restore_live_ui_target_resume "${ui_resume_state}" "${ui_resume_log}" "${ui_resume_env[@]}"
      stop_ios_runtime_log_capture "${UI_LOG_PID}"
      exit "${ui_status}"
    fi
  fi
  stop_ios_runtime_log_capture "${UI_LOG_PID}"
  UI_LOG_PID=""
  collect_ios_deep_evidence_file "${ui_runtime_log}"
  restore_live_ui_target_resume "${ui_resume_state}" "${ui_resume_log}" "${ui_resume_env[@]}"
}

echo "Run artifacts: ${RUN_DIR}"
missing=0
require_value REELFIN_TEST_SERVER_URL "${qa_server_url}" || missing=1
require_value REELFIN_TEST_USERNAME "${qa_username}" || missing=1
require_value REELFIN_TEST_PASSWORD "${qa_password}" || missing=1
require_value TEST_DIRECTPLAY_MP4_ITEM_ID "${qa_directplay_item_id}" || missing=1
require_value TEST_MKV_ITEM_ID "${qa_mkv_item_id}" || missing=1
require_value TEST_HDR_ITEM_ID "${qa_hdr_item_id}" || missing=1
require_value TEST_DOLBY_VISION_ITEM_ID "${qa_dv_item_id}" || missing=1
if [[ "${missing}" -ne 0 ]]; then
  echo "Fix missing values before live player E2E."
  exit 2
fi

echo
echo "Regenerating Xcode project..."
run_logged "${RUN_DIR}/xcodegen.log" env -i PATH="${PATH}" HOME="${QA_HOME}" \
  DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}" xcodegen generate

echo
echo "Running explicit Jellyfin item probes..."
run_logged "${RUN_DIR}/explicit-item-probes.log" "${base_child_env[@]}" \
  JELLYFIN_BASE_URL="${qa_server_url}" JELLYFIN_USERNAME="${qa_username}" JELLYFIN_PASSWORD="${qa_password}" \
  TEST_DIRECTPLAY_MP4_ITEM_ID="${qa_directplay_item_id}" TEST_MKV_ITEM_ID="${qa_mkv_item_id}" \
  TEST_HDR_ITEM_ID="${qa_hdr_item_id}" TEST_DOLBY_VISION_ITEM_ID="${qa_dv_item_id}" \
  "${PYTHON_RUNNER}" scripts/live_directplay_item_probe.py

echo
echo "Running live Jellyfin resume reporting probe..."
run_logged "${RUN_DIR}/resume-reporting-probe.log" "${base_child_env[@]}" \
  JELLYFIN_BASE_URL="${qa_server_url}" JELLYFIN_USERNAME="${qa_username}" JELLYFIN_PASSWORD="${qa_password}" \
  TEST_DIRECTPLAY_MP4_ITEM_ID="${qa_directplay_item_id}" \
  "${PYTHON_RUNNER}" scripts/live_resume_reporting_probe.py

echo
echo "Running live original-stream benchmark..."
run_logged "${RUN_DIR}/original-stream-benchmark.log" "${base_child_env[@]}" \
  JELLYFIN_BASE_URL="${qa_server_url}" JELLYFIN_USERNAME="${qa_username}" JELLYFIN_PASSWORD="${qa_password}" \
  TEST_DIRECTPLAY_MP4_ITEM_ID="${qa_directplay_item_id}" TEST_MKV_ITEM_ID="${qa_mkv_item_id}" \
  TEST_HDR_ITEM_ID="${qa_hdr_item_id}" TEST_DOLBY_VISION_ITEM_ID="${qa_dv_item_id}" \
  "${PYTHON_RUNNER}" scripts/live_player_benchmark.py \
  --range-loops "${LOOPS}" \
  --json-out "${TRANSIENT_ROOT}/original-stream-benchmark.json"

echo
echo "Running live playback URL probe loop..."
run_logged "${RUN_DIR}/live-playback-probe.log" "${base_child_env[@]}" \
  REELFIN_TEST_SERVER_URL="${qa_server_url}" REELFIN_TEST_USERNAME="${qa_username}" REELFIN_TEST_PASSWORD="${qa_password}" \
  TEST_DIRECTPLAY_MP4_ITEM_ID="${qa_directplay_item_id}" TEST_MKV_ITEM_ID="${qa_mkv_item_id}" \
  TEST_DOLBY_VISION_ITEM_ID="${qa_dv_item_id}" \
  "${PYTHON_RUNNER}" scripts/live_playback_probe.py \
  --loops "${LOOPS}" \
  --sample-size "${SAMPLE_SIZE}" \
  --max-failures "${MAX_FAILURES}"

echo
echo "Running deterministic iOS playback tests..."
run_logged "${RUN_DIR}/xcodebuild-playback-tests.log" "${base_child_env[@]}" \
  REELFIN_TEST_SERVER_URL="${qa_server_url}" REELFIN_TEST_USERNAME="${qa_username}" REELFIN_TEST_PASSWORD="${qa_password}" \
  TEST_DIRECTPLAY_MP4_ITEM_ID="${qa_directplay_item_id}" TEST_MKV_ITEM_ID="${qa_mkv_item_id}" \
  TEST_HDR_ITEM_ID="${qa_hdr_item_id}" TEST_DOLBY_VISION_ITEM_ID="${qa_dv_item_id}" \
  REELFIN_TEST_LOOPS="${LOOPS}" REELFIN_TEST_SAMPLE_SIZE="${SAMPLE_SIZE}" REELFIN_TEST_MAX_FAILURES="${MAX_FAILURES}" \
  REELFIN_TEST_EXPLICIT_ONLY="${qa_explicit_only}" REELFIN_TEST_DIRECTPLAY_ONLY="${qa_directplay_only}" \
  xcodebuild test \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination "${IOS_DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -only-testing:PlaybackEngineTests/NativePlayerSessionRoutingTests \
  -only-testing:PlaybackEngineTests/NativePlayerPlaybackControllerEndToEndTests \
  -only-testing:PlaybackEngineTests/NativePlaybackPlannerTests \
  -only-testing:PlaybackEngineTests/NativePlayerRouteGuardTests \
  -only-testing:PlaybackEngineTests/NativePlayerConfigurationTests \
  -only-testing:PlaybackEngineTests/PlaybackStopReportingTests \
  -only-testing:PlaybackEngineTests/CapabilityEngineTests \
  -only-testing:PlaybackEngineTests/PlaybackAssetSelectionOptimizationTests \
  -only-testing:PlaybackEngineTests/PlaybackResumeSeekPlannerTests \
  -only-testing:PlaybackEngineTests/PlaybackIntegrationProbeTests/testLiveServerPlaybackProbeLoop

if [[ "${RUN_UI}" -eq 1 ]]; then
  echo
  run_live_ui_gate "directplay-mp4" "" "LiveUI" "0" "1" "${qa_ui_smoke_seconds}"
  run_live_ui_gate "directplay-hdr-dv-long" "-hdr-dv-long" "LiveUI-hdr-dv-long" "0" "1" "${qa_ui_long_seconds}"
  run_live_ui_gate "samplebuffer-mkv" "-samplebuffer" "LiveUI-samplebuffer" "1" "1" "${qa_ui_smoke_seconds}"
fi

if [[ "${RUN_TVOS}" -eq 1 ]]; then
  echo
  echo "Running tvOS build gate..."
  run_logged "${RUN_DIR}/xcodebuild-tvos-build.log" "${base_child_env[@]}" xcodebuild build \
    -project ReelFin.xcodeproj \
    -scheme ReelFinTV \
    -destination "${TVOS_DESTINATION}" \
    -derivedDataPath "${TVOS_DERIVED_DATA_PATH}"
fi

echo
echo "Scanning player runtime logs for known fatal playback signatures..."
run_logged "${RUN_DIR}/runtime-log-cleanliness.log" "${base_child_env[@]}" "${PYTHON_RUNNER}" scripts/assert_player_runtime_log_clean.py "${RUN_DIR}"

echo
echo "Checking deep player playback evidence..."
run_logged "${RUN_DIR}/deep-playback-evidence.log" "${base_child_env[@]}" "${PYTHON_RUNNER}" scripts/assert_player_deep_playback_evidence.py \
  "${RUN_DIR}" \
  --min-observed-seconds "${qa_deep_min_seconds}" \
  --min-ticks "${qa_deep_min_ticks}" \
  --require-avplayer-scenario "directplay-mp4:${qa_deep_min_seconds}:${qa_deep_min_ticks}:0:0" \
  --require-avplayer-scenario "directplay-hdr-dv-long:${qa_deep_directplay_seconds}:${qa_deep_min_ticks}:1:1" \
  --require-dv \
  --require-samplebuffer

scan_retained_artifacts
ARTIFACT_SCAN_COMPLETE=1

echo
echo "ReelFin player E2E finished."
echo "Artifacts: ${RUN_DIR}"
