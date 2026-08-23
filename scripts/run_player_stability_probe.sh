#!/usr/bin/env bash
set -euo pipefail

# Player stability probe: repeated live playback smoke runs with full log capture,
# then aggregation of stall/underrun/first-frame telemetry into summary.md + summary.json.
#
# Usage: run_player_stability_probe.sh [loops>=1] [simulator-device-id]
# Requires an authenticated session on the simulator (same prerequisite as
# run_player_ui_probe.sh) for the live smoke tests to actually play.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOPS="${1:-3}"
DESTINATION_ID="${2:-}"
ARTIFACT_ROOT="${ROOT_DIR}/.artifacts/player-stability"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
RUN_DIR="${ARTIFACT_ROOT}/${TIMESTAMP}"
RESULT_BUNDLE="${RUN_DIR}/PlayerStability.xcresult"
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

echo "Player stability probe: ${LOOPS} loop(s) on simulator ${DESTINATION_ID}"
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

for ((i=1; i<=LOOPS; i++)); do
  echo
  echo "=== STABILITY LOOP ${i}/${LOOPS} ==="
  xcodebuild test \
    -project ReelFin.xcodeproj \
    -scheme ReelFin \
    -destination "id=${DESTINATION_ID}" \
    -only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testExistingSessionMoviePlaybackSmoke \
    -only-testing:ReelFinUITests/PlaybackLiveSmokeUITests/testExistingSessionSeriesPlaybackSmoke \
    | tee "${RUN_DIR}/xcodebuild-loop-${i}.log"
done

echo
echo "Aggregating stability metrics..."

python3 - "${RUN_DIR}" <<'PYEOF'
import json
import re
import statistics
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
log_path = run_dir / "reelfin.log"
text = log_path.read_text(errors="replace") if log_path.exists() else ""

def counts(pattern):
    return len(re.findall(pattern, text, re.MULTILINE))

def float_values(pattern):
    return [float(m) for m in re.findall(pattern, text)]

def last_value(pattern):
    values = float_values(pattern)
    return values[-1] if values else None

loop_logs = sorted(run_dir.glob("xcodebuild-loop-*.log"))

summary = {
    "loops": len(loop_logs),
    "session_starts": counts(r"playback\.session\.start"),
    "first_frames": {
        "count": counts(r"avplayer\.first-frame"),
        "elapsed_ms": sorted(float_values(r"avplayer\.first-frame.*?elapsedMs=([0-9.]+)")),
    },
    "audio_starvation_events": counts(r"nativeplayer\.audio\.starvation"),
    "audio_starvation_elapsed_s": float_values(r"nativeplayer\.audio\.starvation.*?elapsed=([0-9.]+)"),
    "audio_ahead_low_events": counts(r"nativeplayer\.audio\.ahead_low"),
    "prefetch_escalations": counts(r"playback\.cache\.prefetch\.escalate"),
    "queue_capacity_upgrades": counts(r"nativeplayer\.queue\.capacity"),
    "underruns_max": last_value(r"audioUnderruns=([0-9]+)"),
    "rebuffers_max": last_value(r"audioRebuffers=([0-9]+)"),
    "buffering_ready_events": counts(r"nativeplayer\.buffering\.ready"),
    "startup_failures": counts(r"playback\.startup\.failure"),
    "watchdog_warnings": counts(r"playback\.watchdog\.(?:startup|decoded_frame)"),
    "fallbacks_triggered": counts(r"playback\.fallback\.triggered"),
    "stall_warnings": counts(r"Playback stalled\."),
    "dropped_frames_last": last_value(r"droppedFrames=([0-9]+)"),
    "drift_ms_samples": float_values(r"avDriftMs=(-?[0-9.]+)"),
}

elapsed = summary["first_frames"]["elapsed_ms"]
drift = [abs(v) for v in summary["drift_ms_samples"]]
report = {
    "loops": summary["loops"],
    "session_starts": summary["session_starts"],
    "first_frame_count": summary["first_frames"]["count"],
    "ttff_median_ms": round(statistics.median(elapsed), 1) if elapsed else None,
    "ttff_max_ms": round(max(elapsed), 1) if elapsed else None,
    "audio_starvation_events": summary["audio_starvation_events"],
    "audio_starvation_total_s": round(sum(summary["audio_starvation_elapsed_s"]), 2),
    "audio_ahead_low_events": summary["audio_ahead_low_events"],
    "prefetch_escalations": summary["prefetch_escalations"],
    "queue_capacity_upgrades": summary["queue_capacity_upgrades"],
    "underruns_last_reported": summary["underruns_max"],
    "rebuffers_last_reported": summary["rebuffers_max"],
    "buffering_ready_events": summary["buffering_ready_events"],
    "startup_failures": summary["startup_failures"],
    "watchdog_warnings": summary["watchdog_warnings"],
    "fallbacks_triggered": summary["fallbacks_triggered"],
    "stall_warnings": summary["stall_warnings"],
    "dropped_frames_last_reported": summary["dropped_frames_last"],
    "abs_drift_median_ms": round(statistics.median(drift), 1) if drift else None,
    "abs_drift_p95_ms": round(sorted(drift)[int(0.95 * (len(drift) - 1))], 1) if drift else None,
}

(run_dir / "summary.json").write_text(json.dumps(report, indent=2) + "\n")

lines = ["# Player Stability Summary", ""]
for key, value in report.items():
    lines.append(f"- {key}: {value}")
lines += ["", "## Raw markers", ""]
lines.append("- audio.starvation lines: `grep 'nativeplayer.audio.starvation' reelfin.log`")
lines.append("- deep ticks: `grep 'playback.deep.tick\\|nativeplayer.deep.tick' reelfin.log`")
(run_dir / "summary.md").write_text("\n".join(lines) + "\n")

print(json.dumps(report, indent=2))
PYEOF

echo
echo "Player stability probe finished."
echo "Summary: ${RUN_DIR}/summary.md"
echo "Raw log: ${RUN_DIR}/reelfin.log"
