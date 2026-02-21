# Playback Profiling (iOS + tvOS)

## Instrumentation added

- `playback_info_request`: Jellyfin PlaybackInfo request latency.
- `playback_url_selection`: source scoring + route selection latency.
- `avplayer_item_ready`: time from item creation to `readyToPlay`.
- `avplayer_first_frame`: end-to-end `time-to-first-frame` (TTFF).
- `playback_stall`: each buffering stall interval until recovery.

Signpost categories are emitted from:
- `Signpost.playbackInfo`
- `Signpost.playbackSelection`
- `Signpost.playerLifecycle`
- `Signpost.playbackStalls`

## Runtime metrics exposed in debug overlay

- Container (MP4/HLS/etc)
- Video codec
- Bit depth
- HDR mode (`Dolby Vision`, `HDR10`, `SDR`, `Unknown`)
- Audio mode (`Dolby Atmos`, `E-AC-3`, etc)
- Bitrate (when available from access log)
- Play method (`DirectPlay`, `DirectStream`, `Transcode`)
- TTFF (ms)
- Stall count
- Dropped frames

## How to profile in Instruments

1. Run app on real device (preferred for HDR/Atmos validation).
2. Open Instruments and use:
   - **Points of Interest** (for signposts)
   - **Time Profiler** (CPU spikes during playback start/stalls)
   - **Network** (PlaybackInfo + segment fetch behavior)
3. Start playback for one SDR title and one Dolby Vision + Atmos title.
4. Validate:
   - TTFF target: < 1500 ms on warm path.
   - Stall count target: 0 on LAN, low single-digit on WAN.
   - Dropped frames trend: near 0 for stable streams.
   - Route target: `DirectPlay` first, then `DirectStream`, `Transcode` last.
5. Inspect signpost gaps:
   - high `playback_info_request`: server/API latency
   - high `avplayer_item_ready`: manifest/asset preparation issue
   - frequent `playback_stall`: bitrate too high / poor network / buffer policy mismatch

## HDR / EDR references (Apple)

- [Editing and playing HDR video](https://developer.apple.com/documentation/AVFoundation/editing-and-playing-hdr-video)
- [Explore HDR rendering with EDR (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10161/)
- [Edit and play back HDR video with AVFoundation (WWDC20)](https://developer.apple.com/videos/play/wwdc2020/10009/)

Best-practice alignment in this module:
- AVPlayer/AVFoundation primary playback path.
- Preserve HEVC Main10/Dolby Vision via direct play or HLS remux when possible.
- Use transcode only as last fallback.
- Use runtime diagnostics from media metadata + AVPlayer access logs.
