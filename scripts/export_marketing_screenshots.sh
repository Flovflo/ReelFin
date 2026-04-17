#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STUDIO_DIR="$ROOT_DIR/AppStore/ScreenshotStudio"
OUTPUT_DIR="$ROOT_DIR/AppStore/MarketingScreenshotsIOS"
HOST="127.0.0.1"
PORT="4300"
SERVER_LOG="${TMPDIR:-/tmp}/reelfin-screenshot-studio.log"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

cd "$STUDIO_DIR"
bun install >/dev/null
bun run build >/dev/null
bun run start -- --hostname "$HOST" --port "$PORT" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

cleanup() {
  kill "$SERVER_PID" >/dev/null 2>&1 || true
  wait "$SERVER_PID" >/dev/null 2>&1 || true
}

trap cleanup EXIT

for _ in {1..60}; do
  if curl -fsS "http://$HOST:$PORT" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

capture() {
  local size_id="$1"
  local folder="$2"
  local width="$3"
  local height="$4"
  local slide_id="$5"
  local order="$6"
  local out_dir="$OUTPUT_DIR/$folder"
  local output_file="$out_dir/${order}-${slide_id}.png"

  mkdir -p "$out_dir"

  chromium \
    --headless \
    --disable-gpu \
    --hide-scrollbars \
    --force-device-scale-factor=1 \
    --run-all-compositor-stages-before-draw \
    --virtual-time-budget=16000 \
    --window-size="${width},${height}" \
    --screenshot="$output_file" \
    "http://$HOST:$PORT/?size=${size_id}&slide=${slide_id}&export=1" \
    >/dev/null 2>&1

  echo "Exported ${output_file#$ROOT_DIR/}"
}

capture iphone-6.9 "iphone-6.9-inch" 1320 2868 home 01
capture iphone-6.9 "iphone-6.9-inch" 1320 2868 detail 02
capture iphone-6.9 "iphone-6.9-inch" 1320 2868 library 03

capture iphone-6.5 "iphone-6.5-inch" 1284 2778 home 01
capture iphone-6.5 "iphone-6.5-inch" 1284 2778 detail 02
capture iphone-6.5 "iphone-6.5-inch" 1284 2778 library 03

capture iphone-6.3 "iphone-6.3-inch" 1206 2622 home 01
capture iphone-6.3 "iphone-6.3-inch" 1206 2622 detail 02
capture iphone-6.3 "iphone-6.3-inch" 1206 2622 library 03

capture iphone-6.1 "iphone-6.1-inch" 1125 2436 home 01
capture iphone-6.1 "iphone-6.1-inch" 1125 2436 detail 02
capture iphone-6.1 "iphone-6.1-inch" 1125 2436 library 03

echo "iOS marketing screenshots exported to ${OUTPUT_DIR#$ROOT_DIR/}"
