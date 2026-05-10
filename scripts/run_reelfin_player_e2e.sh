#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REELFIN_E2E_ENV_FILE:-${ROOT_DIR}/.artifacts/secrets/reelfin-e2e.env}"
ARTIFACT_ROOT="${ROOT_DIR}/.artifacts/player-e2e"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="${ARTIFACT_ROOT}/${TIMESTAMP}"
LIVE_UI_TARGET_ENV="${ARTIFACT_ROOT}/live-ui-target.env"
DERIVED_DATA_PATH="${RUN_DIR}/DerivedData"
IOS_DESTINATION="${REELFIN_E2E_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.3.1}"
TVOS_DESTINATION="${REELFIN_E2E_TVOS_DESTINATION:-platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2}"
LOOPS="${REELFIN_TEST_LOOPS:-2}"
SAMPLE_SIZE="${REELFIN_TEST_SAMPLE_SIZE:-8}"
MAX_FAILURES="${REELFIN_TEST_MAX_FAILURES:-0}"
RUN_UI=1
RUN_TVOS=1

usage() {
  cat <<USAGE
Usage: $0 [--env-file path] [--loops n] [--sample-size n] [--max-failures n] [--skip-ui] [--skip-tvos]

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
      ENV_FILE="$2"
      shift 2
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

mkdir -p "${RUN_DIR}"
cd "${ROOT_DIR}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing env file: ${ENV_FILE}"
  exit 2
fi

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
    if [[ "${value}" == \"*\" && "${value}" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    export "${key}=${value}"
  done < "${ENV_FILE}"
}

load_env_file

export REELFIN_TEST_SERVER_URL="${REELFIN_TEST_SERVER_URL:-${JELLYFIN_BASE_URL:-}}"
export REELFIN_TEST_USERNAME="${REELFIN_TEST_USERNAME:-${JELLYFIN_USERNAME:-}}"
export REELFIN_TEST_PASSWORD="${REELFIN_TEST_PASSWORD:-${JELLYFIN_PASSWORD:-}}"
export TEST_MKV_ITEM_ID="${TEST_MKV_ITEM_ID:-${TEST_MKV_DOLBY_VISION_ITEM_ID:-}}"
export TEST_DOLBY_VISION_ITEM_ID="${TEST_DOLBY_VISION_ITEM_ID:-${TEST_DIRECTPLAY_DOLBY_VISION_ITEM_ID:-${TEST_MKV_DOLBY_VISION_ITEM_ID:-}}}"
export TEST_HDR_ITEM_ID="${TEST_HDR_ITEM_ID:-${TEST_DOLBY_VISION_ITEM_ID:-}}"
export REELFIN_TEST_LOOPS="${LOOPS}"
export REELFIN_TEST_SAMPLE_SIZE="${SAMPLE_SIZE}"
export REELFIN_TEST_MAX_FAILURES="${MAX_FAILURES}"
export REELFIN_TEST_EXPLICIT_ONLY="${REELFIN_TEST_EXPLICIT_ONLY:-1}"
export REELFIN_TEST_DIRECTPLAY_ONLY="${REELFIN_TEST_DIRECTPLAY_ONLY:-1}"
export REELFIN_LIVE_UI_OBSERVE_SECONDS="${REELFIN_LIVE_UI_OBSERVE_SECONDS:-45}"
export REELFIN_PLAYER_DEEP_EVIDENCE="${REELFIN_PLAYER_DEEP_EVIDENCE:-1}"
export SIMCTL_CHILD_REELFIN_TEST_SERVER_URL="${REELFIN_TEST_SERVER_URL}"
export SIMCTL_CHILD_REELFIN_TEST_USERNAME="${REELFIN_TEST_USERNAME}"
export SIMCTL_CHILD_REELFIN_TEST_PASSWORD="${REELFIN_TEST_PASSWORD}"
export SIMCTL_CHILD_REELFIN_TEST_LOOPS="${REELFIN_TEST_LOOPS}"
export SIMCTL_CHILD_REELFIN_TEST_SAMPLE_SIZE="${REELFIN_TEST_SAMPLE_SIZE}"
export SIMCTL_CHILD_REELFIN_TEST_MAX_FAILURES="${REELFIN_TEST_MAX_FAILURES}"
export SIMCTL_CHILD_REELFIN_TEST_EXPLICIT_ONLY="${REELFIN_TEST_EXPLICIT_ONLY}"
export SIMCTL_CHILD_REELFIN_TEST_DIRECTPLAY_ONLY="${REELFIN_TEST_DIRECTPLAY_ONLY}"
export SIMCTL_CHILD_REELFIN_LIVE_UI_OBSERVE_SECONDS="${REELFIN_LIVE_UI_OBSERVE_SECONDS}"
export SIMCTL_CHILD_REELFIN_PLAYER_DEEP_EVIDENCE="${REELFIN_PLAYER_DEEP_EVIDENCE}"
export SIMCTL_CHILD_TEST_DIRECTPLAY_MP4_ITEM_ID="${TEST_DIRECTPLAY_MP4_ITEM_ID:-}"
export SIMCTL_CHILD_TEST_MKV_ITEM_ID="${TEST_MKV_ITEM_ID:-}"
export SIMCTL_CHILD_TEST_HDR_ITEM_ID="${TEST_HDR_ITEM_ID:-}"
export SIMCTL_CHILD_TEST_DOLBY_VISION_ITEM_ID="${TEST_DOLBY_VISION_ITEM_ID:-}"
export JELLYFIN_SERVER="${JELLYFIN_SERVER:-${REELFIN_TEST_SERVER_URL}}"
export JELLYFIN_USER="${JELLYFIN_USER:-${REELFIN_TEST_USERNAME}}"
export JELLYFIN_PASS="${JELLYFIN_PASS:-${REELFIN_TEST_PASSWORD}}"

require_value() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "${value}" || "${value}" == "..." ]]; then
    echo "${name}=MISSING_OR_PLACEHOLDER"
    return 1
  fi
  echo "${name}=SET"
}

redact_xcode_ui_log() {
  python3 -c '
import re
import sys

credential_type = re.compile(r"(Type )'\''[^'\'']*'\''( into \"login_(?:server|username|password)_field\" (?:Secure)?TextField)")
for line in sys.stdin:
    line = credential_type.sub(r"\1'\''<redacted>'\''\2", line)
    if "placeholder = Password" in line:
        line = re.sub(r"text = '\''[^'\'']*'\'' \(length = \d+\)", "text = '\''<redacted>'\'' (length = <redacted>)", line)
    sys.stdout.write(line)
'
}

ios_simulator_name() {
  sed -E 's/.*(^|,)name=([^,]+).*/\2/' <<< "${IOS_DESTINATION}"
}

ios_simulator_device() {
  local simulator_name
  simulator_name="$(ios_simulator_name)"
  xcrun simctl list devices -j | SIM_NAME="${simulator_name}" python3 -c '
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

start_ios_runtime_log_capture() {
  local output_file="$1"
  local simulator_device
  simulator_device="$(ios_simulator_device)"
  : > "${output_file}"
  xcrun simctl spawn "${simulator_device}" log stream \
    --style compact \
    --level debug \
    --predicate 'subsystem == "com.reelfin.app" OR process == "ReelFin" OR process == "ReelFinUITests-Runner"' \
    > "${output_file}" 2>&1 &
  echo "$!"
}

stop_ios_runtime_log_capture() {
  local pid="${1:-}"
  [[ -z "${pid}" ]] && return 0
  kill "${pid}" >/dev/null 2>&1 || true
  wait "${pid}" >/dev/null 2>&1 || true
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

  local evidence_file="${container_path}/Documents/reelfin-player-deep-evidence.log"
  if [[ ! -f "${evidence_file}" ]]; then
    echo "WARN player deep evidence file missing" >> "${output_file}"
    return 0
  fi

  {
    echo
    echo "----- player deep evidence file -----"
    cat "${evidence_file}"
  } >> "${output_file}"
}

run_live_ui_smoke_test() {
  local result_bundle="$1"
  xcodebuild test \
    -project ReelFin.xcodeproj \
    -scheme ReelFin \
    -destination "${IOS_DESTINATION}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -resultBundlePath "${result_bundle}" \
    -only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testLiveLoginAndStartPlayback
}

restore_live_ui_target_resume() {
  local state_file="$1"
  local log_file="$2"
  if [[ ! -f "${state_file}" ]]; then
    return 0
  fi
  if ! python3 scripts/live_ui_resume_target.py restore \
    --state-file "${state_file}" \
    | tee -a "${log_file}"; then
    echo "WARN live UI resume restore failed for ${state_file}" | tee -a "${log_file}"
  fi
}

write_live_ui_target_env() {
  local target_item_id="$1"
  local expect_custom_controls="$2"
  local open_target_directly="$3"
  umask 077
  {
    printf 'REELFIN_LIVE_UI_TARGET_ITEM_ID=%s\n' "${target_item_id}"
    printf 'REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS=%s\n' "${expect_custom_controls}"
    printf 'REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY=%s\n' "${open_target_directly}"
    printf 'REELFIN_LIVE_UI_OBSERVE_SECONDS=%s\n' "${REELFIN_LIVE_UI_OBSERVE_SECONDS}"
    printf 'REELFIN_PLAYER_DEEP_EVIDENCE=%s\n' "${REELFIN_PLAYER_DEEP_EVIDENCE}"
    printf 'REELFIN_PLAYER_DEEP_EVIDENCE_RESET=1\n'
  } > "${LIVE_UI_TARGET_ENV}"
}

clear_live_ui_target_env() {
  rm -f "${LIVE_UI_TARGET_ENV}" >/dev/null 2>&1 || true
  unset REELFIN_LIVE_UI_TARGET_ITEM_ID
  unset SIMCTL_CHILD_REELFIN_LIVE_UI_TARGET_ITEM_ID
  unset REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS
  unset SIMCTL_CHILD_REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS
  unset REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY
  unset SIMCTL_CHILD_REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY
  unset REELFIN_PLAYER_DEEP_EVIDENCE_RESET
  unset SIMCTL_CHILD_REELFIN_PLAYER_DEEP_EVIDENCE_RESET
}

run_live_ui_gate() {
  local label="$1"
  local target_item_id="$2"
  local log_suffix="$3"
  local result_name="$4"
  local expect_custom_controls="${5:-0}"
  local open_target_directly="${6:-0}"
  local ui_runtime_log="${RUN_DIR}/ios-live-ui${log_suffix}-runtime.stream"
  local ui_xcode_log="${RUN_DIR}/xcodebuild-live-ui${log_suffix}.log"
  local ui_resume_log="${RUN_DIR}/live-ui${log_suffix}-resume-target.log"
  local ui_resume_state="${RUN_DIR}/live-ui${log_suffix}-resume-target.json"

  echo "Running live iOS UI smoke test (${label})..."
  python3 scripts/live_ui_resume_target.py prepare \
    --item-id "${target_item_id}" \
    --state-file "${ui_resume_state}" \
    | tee "${ui_resume_log}"
  write_live_ui_target_env "${target_item_id}" "${expect_custom_controls}" "${open_target_directly}"
  export REELFIN_LIVE_UI_TARGET_ITEM_ID="${target_item_id}"
  export SIMCTL_CHILD_REELFIN_LIVE_UI_TARGET_ITEM_ID="${target_item_id}"
  export REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS="${expect_custom_controls}"
  export SIMCTL_CHILD_REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS="${expect_custom_controls}"
  export REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY="${open_target_directly}"
  export SIMCTL_CHILD_REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY="${open_target_directly}"
  export REELFIN_PLAYER_DEEP_EVIDENCE_RESET=1
  export SIMCTL_CHILD_REELFIN_PLAYER_DEEP_EVIDENCE_RESET=1
  settle_ios_simulator_for_ui_test
  ui_log_pid="$(start_ios_runtime_log_capture "${ui_runtime_log}")"
  trap 'stop_ios_runtime_log_capture "${ui_log_pid:-}"' EXIT
  set +e
  run_live_ui_smoke_test "${RUN_DIR}/${result_name}.xcresult" \
    | redact_xcode_ui_log \
    | tee "${ui_xcode_log}"
  ui_status="${PIPESTATUS[0]}"
  set -e
  if [[ "${ui_status}" -ne 0 ]]; then
    if grep -Eq 'Application failed preflight checks|reason: Busy|Simulator device failed to launch' "${ui_xcode_log}"; then
      echo "Retrying live iOS UI smoke test (${label}) after simulator busy preflight..."
      settle_ios_simulator_for_ui_test
      set +e
      run_live_ui_smoke_test "${RUN_DIR}/${result_name}-retry.xcresult" \
        | redact_xcode_ui_log \
        | tee "${RUN_DIR}/xcodebuild-live-ui${log_suffix}-retry.log"
      retry_status="${PIPESTATUS[0]}"
      set -e
      if [[ "${retry_status}" -ne 0 ]]; then
        restore_live_ui_target_resume "${ui_resume_state}" "${ui_resume_log}"
        clear_live_ui_target_env
        stop_ios_runtime_log_capture "${ui_log_pid}"
        exit "${retry_status}"
      fi
    else
      restore_live_ui_target_resume "${ui_resume_state}" "${ui_resume_log}"
      clear_live_ui_target_env
      stop_ios_runtime_log_capture "${ui_log_pid}"
      exit "${ui_status}"
    fi
  fi
  stop_ios_runtime_log_capture "${ui_log_pid}"
  collect_ios_deep_evidence_file "${ui_runtime_log}"
  restore_live_ui_target_resume "${ui_resume_state}" "${ui_resume_log}"
  clear_live_ui_target_env
  trap - EXIT
}

echo "Run artifacts: ${RUN_DIR}"
echo "Env file: ${ENV_FILE}"
missing=0
for key in \
  REELFIN_TEST_SERVER_URL \
  REELFIN_TEST_USERNAME \
  REELFIN_TEST_PASSWORD \
  TEST_DIRECTPLAY_MP4_ITEM_ID \
  TEST_MKV_ITEM_ID \
  TEST_HDR_ITEM_ID \
  TEST_DOLBY_VISION_ITEM_ID; do
  require_value "${key}" || missing=1
done
if [[ "${missing}" -ne 0 ]]; then
  echo "Fix missing values before live player E2E."
  exit 2
fi

echo
echo "Regenerating Xcode project..."
xcodegen generate | tee "${RUN_DIR}/xcodegen.log"

echo
echo "Running explicit Jellyfin item probes..."
python3 scripts/live_directplay_item_probe.py | tee "${RUN_DIR}/explicit-item-probes.log"

echo
echo "Running live Jellyfin resume reporting probe..."
python3 scripts/live_resume_reporting_probe.py | tee "${RUN_DIR}/resume-reporting-probe.log"

echo
echo "Running live original-stream benchmark..."
python3 scripts/live_player_benchmark.py \
  --range-loops "${LOOPS}" \
  --json-out "${RUN_DIR}/original-stream-benchmark.json" \
  | tee "${RUN_DIR}/original-stream-benchmark.log"

echo
echo "Running live playback URL probe loop..."
python3 scripts/live_playback_probe.py \
  --loops "${LOOPS}" \
  --sample-size "${SAMPLE_SIZE}" \
  --max-failures "${MAX_FAILURES}" \
  | tee "${RUN_DIR}/live-playback-probe.log"

echo
echo "Running deterministic iOS playback tests..."
xcodebuild test \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination "${IOS_DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -resultBundlePath "${RUN_DIR}/PlaybackEngine.xcresult" \
  -only-testing:PlaybackEngineTests/NativePlayerSessionRoutingTests \
  -only-testing:PlaybackEngineTests/NativePlayerPlaybackControllerEndToEndTests \
  -only-testing:PlaybackEngineTests/NativePlaybackPlannerTests \
  -only-testing:PlaybackEngineTests/NativePlayerRouteGuardTests \
  -only-testing:PlaybackEngineTests/NativePlayerConfigurationTests \
  -only-testing:PlaybackEngineTests/PlaybackStopReportingTests \
  -only-testing:PlaybackEngineTests/CapabilityEngineTests \
  -only-testing:PlaybackEngineTests/PlaybackAssetSelectionOptimizationTests \
  -only-testing:PlaybackEngineTests/PlaybackResumeSeekPlannerTests \
  -only-testing:PlaybackEngineTests/PlaybackIntegrationProbeTests/testLiveServerPlaybackProbeLoop \
  | tee "${RUN_DIR}/xcodebuild-playback-tests.log"

if [[ "${RUN_UI}" -eq 1 ]]; then
  echo
  run_live_ui_gate "directplay-mp4" "${TEST_DIRECTPLAY_MP4_ITEM_ID}" "" "LiveUI" "0" "0"
  run_live_ui_gate "samplebuffer-mkv" "${TEST_MKV_ITEM_ID}" "-samplebuffer" "LiveUI-samplebuffer" "1" "1"
fi

if [[ "${RUN_TVOS}" -eq 1 ]]; then
  echo
  echo "Running tvOS build gate..."
  xcodebuild build \
    -project ReelFin.xcodeproj \
    -scheme ReelFinTV \
    -destination "${TVOS_DESTINATION}" \
    -derivedDataPath "${DERIVED_DATA_PATH}-tvos" \
    | tee "${RUN_DIR}/xcodebuild-tvos-build.log"
fi

echo
echo "Scanning player runtime logs for known fatal playback signatures..."
python3 scripts/assert_player_runtime_log_clean.py "${RUN_DIR}" | tee "${RUN_DIR}/runtime-log-cleanliness.log"

echo
echo "Checking deep player playback evidence..."
python3 scripts/assert_player_deep_playback_evidence.py \
  "${RUN_DIR}" \
  --min-observed-seconds "${REELFIN_DEEP_PLAYBACK_MIN_SECONDS:-20}" \
  --min-ticks "${REELFIN_DEEP_PLAYBACK_MIN_TICKS:-3}" \
  --require-dv \
  --require-samplebuffer \
  | tee "${RUN_DIR}/deep-playback-evidence.log"

echo
echo "ReelFin player E2E finished."
echo "Artifacts: ${RUN_DIR}"
