#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${ROOT_DIR}/.artifacts/zero-stall"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="${ARTIFACT_ROOT}/${TIMESTAMP}"
DERIVED_DATA_DIR="${RUN_DIR}/DerivedData"
SUMMARY_FILE="${RUN_DIR}/summary.txt"

IOS_DESTINATION="platform=iOS Simulator,name=iPhone 17,OS=26.3.1"
TVOS_DESTINATION="platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2"
STARTUP_DETAIL_RESULT_BUNDLE="${RUN_DIR}/startup-detail.xcresult"
SCREENSHOT_RESULT_BUNDLE="${RUN_DIR}/appstore-screenshot-tests.xcresult"

mkdir -p "${RUN_DIR}"
cd "${ROOT_DIR}"

run_step() {
  local step_name="$1"
  local log_file="$2"
  shift 2

  echo
  echo "==> ${step_name}"
  "$@" 2>&1 | tee "${log_file}"
}

run_step "Regenerate Xcode project" "${RUN_DIR}/xcodegen.log" xcodegen generate

run_step "Build ReelFin for iOS" "${RUN_DIR}/build-ios.log" \
  xcodebuild build \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination "${IOS_DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}"

run_step "Build ReelFinTV for tvOS" "${RUN_DIR}/build-tvos.log" \
  xcodebuild build \
  -project ReelFin.xcodeproj \
  -scheme ReelFinTV \
  -destination "${TVOS_DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}"

run_step "Run startup/detail validation tests" "${RUN_DIR}/startup-detail-tests.log" \
  xcodebuild test \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination "${IOS_DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -resultBundlePath "${STARTUP_DETAIL_RESULT_BUNDLE}" \
  -only-testing:PlaybackEngineTests/PlaybackStartupReadinessPolicyTests \
  -only-testing:PlaybackEngineTests/PlaybackStartupPreheaterTests \
  -only-testing:PlaybackEngineTests/DetailViewModelActionTests/testPrepareEpisodePlaybackLatestWinsAcrossWarmupSignals

run_step "Run App Store screenshot tests" "${RUN_DIR}/appstore-screenshot-tests.log" \
  xcodebuild test \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination "${IOS_DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -resultBundlePath "${SCREENSHOT_RESULT_BUNDLE}" \
  -only-testing:ReelFinUITests/AppStoreScreenshotTests

cat > "${SUMMARY_FILE}" <<EOF
Zero-stall validation completed successfully.

Artifacts directory: ${RUN_DIR}
Logs:
- ${RUN_DIR}/xcodegen.log
- ${RUN_DIR}/build-ios.log
- ${RUN_DIR}/build-tvos.log
- ${RUN_DIR}/startup-detail-tests.log
- ${RUN_DIR}/appstore-screenshot-tests.log

Result bundles:
- ${STARTUP_DETAIL_RESULT_BUNDLE}
- ${SCREENSHOT_RESULT_BUNDLE}
EOF

echo
cat "${SUMMARY_FILE}"
