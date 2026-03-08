#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/AppStore/Screenshots"
RESULT_BUNDLE_DIR="$ROOT_DIR/build/app-store-xcresults"
SCHEME="ReelFin"
PROJECT="$ROOT_DIR/ReelFin.xcodeproj"
DESTINATIONS=(
  "iPhone 17 Pro Max"
  "iPhone 16 Pro"
  "iPad Pro 13-inch (M5)"
)

mkdir -p "$OUTPUT_DIR"
mkdir -p "$RESULT_BUNDLE_DIR"
RUN_ID="$(date +%Y%m%d%H%M%S)"

slugify() {
  print -rn -- "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//'
}

export_attachments() {
  local result_bundle="$1"
  local destination_directory="$2"
  local attachment_directory

  attachment_directory="$(mktemp -d "${TMPDIR:-/tmp}/reelfin-attachments.XXXXXX")"
  mkdir -p "$destination_directory"

  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$attachment_directory" \
    >/dev/null

  ruby -rjson -rfileutils -e '
    manifest = JSON.parse(File.read(ARGV[0]))
    source_dir = ARGV[1]
    destination_dir = ARGV[2]

    manifest
      .flat_map { |entry| entry.fetch("attachments", []) }
      .each do |attachment|
        source = File.join(source_dir, attachment.fetch("exportedFileName"))
        suggested = attachment.fetch("suggestedHumanReadableName")
        extension = File.extname(source)
        basename = suggested.sub(/_0_[^.]+\.[^.]+\z/, "")
        destination = File.join(destination_dir, "#{basename}#{extension}")
        FileUtils.cp(source, destination)
      end
  ' "$attachment_directory/manifest.json" "$attachment_directory" "$destination_directory"
}

for device in "${DESTINATIONS[@]}"; do
  slug="$(slugify "$device")"
  result_bundle="$RESULT_BUNDLE_DIR/${slug}-${RUN_ID}.xcresult"
  device_output_directory="$OUTPUT_DIR/$slug"
  echo "Capturing screenshots for $device..."
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$device,OS=26.0" \
    -resultBundlePath "$result_bundle" \
    -only-testing:ReelFinUITests/AppStoreScreenshotTests/testCaptureScreenshots

  export_attachments "$result_bundle" "$device_output_directory"
done

echo "Screenshots exported to $OUTPUT_DIR"
