# Diagnostics

`NativePlayerDiagnostics` is rendered by `NativeVLCPlayerView` when the new feature flag path is active.

Overlay fields include:

- original media requested
- server transcode used
- media source ID
- container
- demuxer
- video codec/backend/hardware flag
- audio codec/backend
- subtitle format
- selected audio/subtitle tracks
- HDR format and Dolby Vision profile
- buffered ranges
- network Mbps
- dropped frames
- decode/render latency
- A/V sync offset
- unsupported modules
- exact failure reason

The overlay is intentionally technical. Unsupported cases should not collapse into generic playback failure.
