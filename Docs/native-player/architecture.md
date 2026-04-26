# Native Player Player Architecture

This branch adds a separate, feature-flagged local media engine path. The existing AVPlayer path remains the production default when `NativePlayerConfig.enabled == false`.

```mermaid
flowchart TD
  Jellyfin["Jellyfin Original File"] --> Resolver["OriginalMediaResolver"]
  Resolver --> Access["HTTPRangeByteSource"]
  Access --> Probe["ContainerProbeService"]
  Probe --> Demux["DemuxerFactory"]
  Demux --> Tracks["Track Registry"]
  Tracks --> Plan["NativePlaybackPlanner"]
  Plan --> VDec["VideoDecoderFactory / VideoToolbox"]
  Plan --> ADec["AudioDecoderFactory / AppleAudioToolbox"]
  Plan --> SSub["Subtitle Parsers"]
  VDec --> VRender["SampleBuffer / Metal Renderer"]
  ADec --> ARender["AVAudioEngine Renderer"]
  SSub --> Overlay["SubtitleOverlayView planned"]
  ARender --> Clock["ClockSynchronizer"]
  VRender --> Clock
  Clock --> Diag["NativePlayerDiagnostics Overlay"]
```

Implemented code lives in `NativeMediaCore/Sources/NativeMediaCore` with integration in `PlaybackEngine/Sources/PlaybackEngine/NativePlayer`.

Current reality: this is an engine foundation, not native-player playback. It requests original media, probes bytes, parses basic Matroska metadata/packets, plans local decode backends, and displays diagnostics. Full packet decode/render playback is still incomplete.
