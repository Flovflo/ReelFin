# Playback Architecture (Beta v0.3)

This document explains the current playback stack inside ReelFin, the decision-making flow, the deterministic fallback profiles, and the constraints we enforce so the app stays Apple-safe on iOS/tvOS.

## Core components
- `MediaSourceResolver`: collects every `DirectStreamUrl` and available metadata for a `MediaSource` (container, codecs, audio/subtitle tracks, HDR tags).
- `PlaybackCapabilityEvaluator`: maps Jellyfin metadata to native capability flags (H.264/HEVC/AC3/AAC, HDR10/Dolby Vision, supported subtitles).
- `PlaybackDecisionEngine`: chooses between `DirectPlay`, `Remux`, and `Transcode` plans, immediately favoring raw assets marked as Apple-compatible.
- `PlaybackCoordinator`: normalizes Jellyfin URLs (container/segment, audio codec, stream copy flags, `BreakOnNonKeyFrames`, `SegmentLength`, and `MinSegments`) before handing them to AVPlayer.
- `NativePlaybackEngine`: wraps AVPlayer/AVPlayerViewController, handles the debug overlay toggle, variant pinning, and VideoToolbox-based enhancements when needed.
- `PlaybackSessionController`: runs watchdog timers, monitors `readyToPlay`, and triggers deterministic recovery steps if the first plan fails.

## Decision flow
1. Ask `MediaSourceResolver` for direct stream URLs; load codec/container metadata from Jellyfin.
2. Use `PlaybackCapabilityEvaluator` to mark each source as supported (mp4/fmp4/HLS + AVC/HEVC/HDR10/DV/AAC/E-AC3).
3. If a supported source exists, immediately request it (raw direct play). The fallback cascade is bypassed unless AVPlayer reports a hard failure.
4. If no compatible direct route exists, fall back to server-driven plans ranked by determinism:
   * `appleOptimizedHEVC`: force `AllowVideoStreamCopy=false`, `Container=fmp4`, `VideoCodec=hevc`, keep `AudioCodec` copy when possible.
   * `conservativeCompatibility`: a middle ground for uncertain hardware by tuning `AllowVideoStreamCopy` and pinning `SegmentLength/MinSegments`.
   * `forceH264Transcode`: last resort; sets `VideoCodec=h264`, `RequireAvc=true`, `Container=ts`, `SegmentContainer=ts`, and `BreakOnNonKeyFrames=false` to minimize startup crashes.

## Profiles & enforcement
| Profile | Purpose | Key query params |
| --- | --- | --- |
| `serverDefault` | Let Jellyfin decide while keeping stream-copy video if safe | keeps `AllowVideoStreamCopy` true when heuristics pass |
| `appleOptimizedHEVC` | Native HEVC path with Apple-friendly parameters | `AllowVideoStreamCopy=false`, `VideoCodec=hevc`, `SegmentContainer=fmp4` |
| `conservativeCompatibility` | Safer fallback for marginal hardware | enforces consistent `SegmentLength`/`MinSegments`, may disable `AllowVideoStreamCopy` |
| `forceH264Transcode` | Stable, SDR AVC path for stuck flows | `VideoCodec=h264`, `RequireAvc=true`, `Container=ts`, `SegmentContainer=ts`, `BreakOnNonKeyFrames=false` |

Every fallback step records the reason for the change; you can see the plan trace in logs/diagnostics when the nerd overlay is enabled.

## Settings & diagnostics
- **Force Raw Direct Play:** stops the decision engine from requesting a remux/transcode URL if an Apple-compatible source already exists. Useful when you trust the server’s metadata.
- **Force H264 Fallback:** pins playback to the `forceH264Transcode` plan, bypassing the other profiles even if HEVC is available—handy for compatibility on older devices and AirPlay mirroring.
- **Debug Overlay:** controlled via `reelfin.playback.debugOverlay.enabled`; when enabled, the overlay surfaces capability outcomes, selected plan, and AVPlayer state strings.

## Constraints
- Native Apple path only. There is no VLCKit, libVLC, or FFmpeg decoding shadowing the decision engine.
- MKV direct play remains unsupported; MKVs always route through remux/transcode.
- HDR10/Dolby Vision flows must stay on HEVC-compatible plans; forcing `forceH264Transcode` converts the output to SDR.
- PGS subtitles and Atmos/TrueHD audio are not played natively—clear them on the server or let a remux/transcode pipeline burn them in.
- Logging lines such as `PlayerRemoteXPC ... err=-12860` or `FigApplicationStateMonitor ... -19431` are expected noise when the watchdog fires; focus on the capability trace instead.

## Testing
Target the playback test suites when modifying decoder decisions or fallback policies.
```sh
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests \
  -only-testing:PlaybackEngineTests/CapabilityEngineTests
```
Add more variant/tests if you touch `HLSVariantSelector` or the `NativeBridge` code paths.

## Staying current
Update this file whenever a new fallback profile is added, AVPlayer handling changes, or debugging toggles move. The README surfaces the high-level mission, but this file contains the flow you must respect to keep playback deterministic.
