# ReelFin

**Status: Beta v0.3**

ReelFin is a native iOS/tvOS client for Jellyfin whose playback strategy is deliberately tuned around Apple frameworks. All rendering, subtitle handling, and diagnostics run through AVFoundation/AVKit (with VideoToolbox where required). The goal is a deterministic, debuggable stack that only falls back to the server when the raw asset is not natively compatible.

## Beta 0.3 highlights
* **Raw-first playback:** we always request the bottles-os stream that Jellyfin marks as Apple-compatible before trying any remux/transcode.
* **Deterministic fallback profiles:** if raw playback fails, the decision engine walks through `appleOptimizedHEVC`, `conservativeCompatibility`, and finally `forceH264Transcode` with specific parameter normalization so the path is predictable.
* **Control your experience:** toggles for `Force raw direct play`, `Force H264 fallback`, and the nerd-overlay/debug logging live in the settings screen so the UI matches the playback policy you intend.
* **No VLC/FFmpeg:** there’s no VLCKit, libVLC, or third-party decoding pipelined into playback—just Apple-native layers.
* **Accountable diagnostics:** logs capture the capability matrix, decision trace, and AVPlayer state when the nerd overlay is enabled, otherwise the player stays clean.

## Playback mission
1. `MediaSourceResolver` collects every `DirectStreamUrl` and metadata from Jellyfin.
2. `PlaybackDecisionEngine` evaluates container/codec, audio tracks, HDR metadata, and subtitle format.
3. If a compatible raw route exists (`mp4`, `fmp4`, AVC/HEVC, HDR10/DV), AVPlayer plays it directly.
4. If the source is not supported natively, we remap to one of the deterministic profiles listed above and normalize the HLS/transcode query parameters (`Container`, `SegmentContainer`, `AudioCodec`, `BreakOnNonKeyFrames`, etc.).
5. `PlaybackSessionController` maintains the AVPlayer lifecycle: watchdog timers, recovery attempts, and variant/pin selection via `HLSVariantSelector`.

## Settings to know
* **Force raw direct play:** prevents the decision engine from requesting remuxed/transcoded URLs when an Apple-compatible source already exists.
* **Force H264 fallback:** when the player cannot decode HDR HEVC reliably, this switch pins playback to AVC so the path is more predictable on older devices and AirPlay.
* **Nerd overlay:** reads `reelfin.playback.debugOverlay.enabled`; enable it to surface capability diagnostics, disable it to keep the player interface clean.

## Docs & architecture
The canonical documentation lives in `Docs/Playback-Architecture-Current.md`. That file describes the architecture blocks (`PlaybackDecisionEngine`, `PlaybackCoordinator`, `NativePlaybackEngine`, etc.), the transcode profiles, and the constraints you must respect when extending playback.

## Testing
```sh
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0' \
  -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests \
  -only-testing:PlaybackEngineTests/CapabilityEngineTests
```

## Contributing
- Keep `PlaybackEngine` tests green when changing playback logic.
- Avoid adding non-native dependencies to the playback path.
- Use the docs above before touching the fallback profiles; they contain the discipline around query parameters and diagnostics.
