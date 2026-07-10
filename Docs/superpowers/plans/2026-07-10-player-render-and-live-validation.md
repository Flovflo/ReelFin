# Player Render and Live Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` inline. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the default iOS/tvOS custom player render a first video frame reliably from real Jellyfin originals, preserve HDR/Dolby Vision, and prove it with live validation instead of surface-only UI checks.

**Architecture:** Keep the Apple-native path (`AVPlayer` → loopback range cache → `AVPlayerViewController`). Replace the custom host's minimal AVKit wrapper with the lifecycle guarantees already proven by the legacy host: stable accessibility anchor, item-ready render-surface reattachment on iOS, and `isReadyForDisplay` evidence. Keep media byte transport separate from presentation; then consolidate probe/on-demand/fill sessions and expose a host-level degradation signal for unreliable origins.

**Tech Stack:** Swift, SwiftUI, AVFoundation, AVKit, XCTest, XcodeGen, Jellyfin live E2E.

## Global Constraints

- Apple-native playback only; no third-party or private media engine.
- Direct Play originals remain the priority path; cache bytes remain authenticated and local-only.
- SDR fallback must be an explicit H.264 server tone-map, never HEVC stream-copy.
- Simulator validates routing, decoding, rendering-state and interaction; HDR/Dolby Vision panel correctness still requires physical Apple TV/display validation.
- Preserve the existing dirty worktree and do not overwrite unrelated player changes.

---

### Task 1: Prove the custom AVKit surface has rendered

**Files:**
- Modify: `Tests/ReelFinUITests/PlaybackLiveSmokeUITests.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`

- [ ] Write a live UI assertion for `custom_player_rendering_ready` after tapping Play/Resume.
- [ ] Run it on the booted iPhone simulator with the explicit real Jellyfin item; record the expected red failure.
- [ ] Give the custom AVKit surface a stable player accessibility marker and publish the ready marker only after `AVPlayerViewController.isReadyForDisplay` with an item in `.readyToPlay`.
- [ ] Re-run the same live test and inspect its screen recording plus simulator logs.

### Task 2: Repair the late-item AVKit render race

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`
- Test: `Tests/ReelFinUITests/PlaybackLiveSmokeUITests.swift`

- [ ] Observe `AVPlayer.currentItem` and item status in the custom surface.
- [ ] On iOS only, pause only when necessary, detach the AVPlayer from `AVPlayerViewController`, then reattach it once after `readyToPlay`; preserve playback intent and suppress SwiftUI reassignment during the short detach.
- [ ] Reinstall rendering readiness observation after attaching and connect it to `CustomPlaybackEngine` first-frame state.
- [ ] Verify with a real deep resume on the 4K HEVC item: first rendered frame, advancing media time, and no persistent black recording.

### Task 3: Make tvOS display negotiation correct

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`
- Modify: `Tests/PlaybackEngineTests/NativeMediaCore/NativePlayerConfigurationTests.swift`

- [ ] Reuse the legacy host's tvOS display-criteria policy in the custom surface.
- [ ] Keep automatic criteria disabled on the tvOS simulator but enabled on device.
- [ ] Add source-level coverage for the shared policy and build both simulator targets.

### Task 4: Consolidate origin-session and cache-start policy

**Files:**
- Modify: `PlaybackEngine/Sources/PlaybackEngine/MediaGateway/OriginDownloader.swift`
- Modify: `PlaybackEngine/Sources/PlaybackEngine/MediaGateway/LocalCacheHTTPServer.swift`
- Modify: `PlaybackEngine/Sources/PlaybackEngine/CustomPlayer/CacheProxySession.swift`
- Test: `Tests/PlaybackEngineTests/PlaybackDropResilienceTests.swift`

- [ ] Write deterministic coverage for the critical startup window: content information plus resume bytes must precede speculative reservoir fill.
- [ ] Reuse a bounded, long-lived media origin session for content probes, on-demand misses and fill windows where the transport allows it.
- [ ] Make a 5xx/timeout visible as a transport fault and retain enough evidence to distinguish it from a renderer failure.
- [ ] Re-run local drop tests plus explicit Jellyfin range benchmarks.

### Task 4A: Never park a cached AVPlayer after `PlaybackStalled`

**Files:**
- Modify: `PlaybackEngine/Sources/PlaybackEngine/CustomPlayer/CustomPlaybackEngine.swift`
- Test: `Tests/PlaybackEngineTests/CustomPlayerSupportTests.swift`

- [ ] Add a failing policy test reproducing the device log: `playbackStalledNotification`, a
      503-second local reservoir, a small residual clock advance, then `rate == 0`.
- [ ] Keep the explicit stall latched until playback is both advancing and actually playing; a
      fractional coast while paused must not be called recovered.
- [ ] On an explicit stall with a trusted local reservoir, request immediate playback on the first
      monitor tick instead of waiting two seconds behind a visible buffering overlay.
- [ ] Re-run the policy tests, the localhost proxy drop tests, and a real Star City playback long
      enough to cross the observed 18.8-second failure point with continuous position/frame logs.

### Task 5: Validate HDR/Dolby Vision and SDR fallback

**Files:**
- Modify as required by the validated failure in `JellyfinOriginalSourceResolver.swift` and `CustomPlaybackEngine.swift`
- Test: `scripts/live_directplay_item_probe.py`, `scripts/live_player_benchmark.py`, `scripts/live_playback_probe.py`

- [ ] Preserve Dolby Vision metadata on the original path and record the selected display policy.
- [ ] Reproduce the current real HLS segment HTTP 500 and distinguish server/transcode configuration from a client URL construction defect.
- [ ] Do not claim SDR fallback readiness until a real H.264 tone-mapped segment and a physical SDR TV pass.

### Task 6: Final evidence gate

- [ ] `xcodegen generate`.
- [ ] Targeted and full iOS tests, iOS build, tvOS build/test.
- [ ] Real Jellyfin explicit-original benchmark, deep-resume UI recording and live fallback probe.
- [ ] Physical Apple TV: Dolby Vision TV, HDR10 TV, SDR TV; record start time, colors, audio/subtitle/seek/resume behavior.
- [ ] Update `PLANS.md` and `OPTIMIZATION_AUDIT.md` with measured evidence and remaining hardware-only caveats.
