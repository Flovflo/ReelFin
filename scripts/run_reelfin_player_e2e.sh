#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REELFIN_E2E_ENV_FILE:-${ROOT_DIR}/.artifacts/secrets/reelfin-e2e.env}"
ARTIFACT_ROOT="${ROOT_DIR}/.artifacts/player-e2e"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="${ARTIFACT_ROOT}/${TIMESTAMP}"
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
export SIMCTL_CHILD_REELFIN_TEST_SERVER_URL="${REELFIN_TEST_SERVER_URL}"
export SIMCTL_CHILD_REELFIN_TEST_USERNAME="${REELFIN_TEST_USERNAME}"
export SIMCTL_CHILD_REELFIN_TEST_PASSWORD="${REELFIN_TEST_PASSWORD}"
export SIMCTL_CHILD_REELFIN_TEST_LOOPS="${REELFIN_TEST_LOOPS}"
export SIMCTL_CHILD_REELFIN_TEST_SAMPLE_SIZE="${REELFIN_TEST_SAMPLE_SIZE}"
export SIMCTL_CHILD_REELFIN_TEST_MAX_FAILURES="${REELFIN_TEST_MAX_FAILURES}"
export SIMCTL_CHILD_REELFIN_TEST_EXPLICIT_ONLY="${REELFIN_TEST_EXPLICIT_ONLY}"
export SIMCTL_CHILD_REELFIN_TEST_DIRECTPLAY_ONLY="${REELFIN_TEST_DIRECTPLAY_ONLY}"
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
  echo "Running live iOS UI smoke test..."
  xcodebuild test \
    -project ReelFin.xcodeproj \
    -scheme ReelFin \
    -destination "${IOS_DESTINATION}" \
    -resultBundlePath "${RUN_DIR}/LiveUI.xcresult" \
    -only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testLiveLoginAndStartPlayback \
    | tee "${RUN_DIR}/xcodebuild-live-ui.log"
fi

if [[ "${RUN_TVOS}" -eq 1 ]]; then
  echo
  echo "Running tvOS build gate..."
  xcodebuild build \
    -project ReelFin.xcodeproj \
    -scheme ReelFinTV \
    -destination "${TVOS_DESTINATION}" \
    | tee "${RUN_DIR}/xcodebuild-tvos-build.log"
fi

echo
echo "Scanning player runtime logs for known fatal playback signatures..."
python3 scripts/assert_player_runtime_log_clean.py "${RUN_DIR}" | tee "${RUN_DIR}/runtime-log-cleanliness.log"

echo
echo "ReelFin player E2E finished."
echo "Artifacts: ${RUN_DIR}"
