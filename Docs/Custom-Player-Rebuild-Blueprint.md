# ReelFin Custom Player — Definitive Rebuild Blueprint

**Branch:** `feat/custom-player-rebuild`
**Status:** build-ready design. Apple-native only (AVFoundation / AVKit / VideoToolbox). iOS 26+.
**Supersedes:** the 9315-line `PlaybackSessionController`, the sample-buffer engine, `NativeBridge`, synthetic HLS, the custom `reelfin-cache://` resource loader, and the 4+ overlapping fallback layers.

This blueprint is the synthesis of three proposals plus their cross-judgments, the AVFoundation/DV spec, and the Infuse-class behavior model. It is decisive: where the proposals contradicted the codebase, the codebase wins. **Two contradictions were verified in-tree and are resolved here, not papered over:**

1. **`MediaGatewayStore.trim(budget:protectedKeys:)` is whole-key only** (verified `MediaGatewayStore.swift:140`). Intra-file "evict-behind-playhead, protect-forward-reservoir, keep-rewind-window" eviction **does not exist** and is explicitly scoped as NEW work (`CacheBudgetManager` + a new `MediaGatewayStore` range-eviction primitive), not a free reuse.
2. **`LocalCacheHTTPServer` depends on `LocalMediaGatewayHTTPRequest` / `LocalMediaGatewayHTTPResponse`** (verified `LocalCacheHTTPServer.swift:113–243`), which live in `LocalMediaGatewayHTTP.swift` — a file inside the "legacy gateway" cluster otherwise slated for deletion. That file is **KEPT/extracted**, not deleted. The kept/deleted boundary is drawn *inside* `MediaGateway/` below.

The custom-scheme files (`CacheResourceLoaderDelegate`, `CachingMediaByteSource`) are referenced by `LocalCacheHTTPServer.swift` only in a **comment** (line 178) — no code dependency — so they delete cleanly.

---

## 0. Design Revision — ORIGINAL-FIRST & FULLY DYNAMIC (user-directed; supersedes any rigid rule below)

This revision overrides the binary "below X Mbps → SDR" framing wherever it appears below. The corrected philosophy:

- **R1 — Keep the ORIGINAL file. Always try.** The custom player feeds AVPlayer the original bytes (DV/HDR) from the local cache. SDR transcode is a **genuine last resort**, not the adaptation plan. Maximize time spent on the original.
- **R2 — Everything DYNAMIC, nothing hardcoded.** No fixed "26 Mbps". Every decision is **relative to the actual `source.bitrate` of the file being played** and the live measured throughput, expressed as ratios (e.g. `measuredMbps / sourceBitrate`, `reservoirSecondsAhead`, `fillRate vs drainRate`). The same code adapts to a 6 Mbps file and a 90 Mbps file with no constants to retune.
- **R3 — A short connection can't carry the original *right now* → BUILD CACHE, don't downgrade.** Instead of switching to SDR, **wait and pre-buffer** the original and **show a loading bar** (progress: reservoir seconds built / target, or %). Like Infuse: a visible buffering indicator while keeping full quality is acceptable; a silent freeze or a quality drop is not. This applies at startup ("attendre d'avoir plus de cache au début") **and** mid-stream (if the reservoir runs low, surface the loading indicator and keep the original).
- **R4 — Smart startup.** Probe the link. Fast link → start quickly (cache builds itself), full DV. Weak link → pre-buffer a cushion first behind a loading bar, then start, so playback runs smooth on the original. The pre-buffer target is dynamic (function of `measuredMbps / sourceBitrate` and the calibrated dropout profile), not a fixed number.
- **R5 — SDR transcode = last resort, decided over TIME, not on a dip.** Only after the link has *sustainably* failed to carry the original — measured throughput stays below the file's bitrate long enough that the reservoir genuinely cannot build (drain ≥ fill across a real window) AND buffering would be repeated/unacceptable. Even then, prefer offering/continuing the original with the loading bar over a forced drop. Distinguish a momentary dip (ride it / buffer it) from a genuine sustained inability (only then SDR). When SDR is finally used, it's still clean tone-mapped H264, never the dark HDR10 path.

**Revised one-line contract:** *Fast when it can be, patient when it must be, always the original when at all possible: it starts quickly on a good link and pre-buffers behind a clear loading bar on a weak one; it holds minutes of the ORIGINAL (Dolby Vision) on disk so dropouts are invisible; when the cache runs low it shows a loading indicator and keeps full quality rather than cutting or dropping; and only a sustained, proven inability to carry the file — measured relative to that file, not a fixed number — ever falls back to clean SDR, never to a dark broken in-between, never to a silent freeze.*

**API impact:** the engine exposes a `bufferingState` the UI binds to — `{ phase: playing | buffering | prerolling, reservoirSeconds, targetSeconds, progress (0–1) }` — so the UI shows a small loading bar when cache is low. Added to §7.

---

## 1. Goals & Non-Negotiables

### Goals
- **Fluid** — steady-state playback is frame-accurate and stutter-free for the whole title.
- **Fast** — first frame ≤ 1.5s (ceiling 2.5s); deep-seek/resume ≤ 4s; cache-hit seek ≤ 0.5s.
- **Never-cut** — any link dropout shorter than the disk reservoir is invisible; the recovery loop never ends on a frozen frame.
- **DV/HDR correct** — true Dolby Vision renders whenever the link can carry it; degraded playback is clean tone-mapped SDR, never dark HDR10, never black.
- **Max, well-managed cache** — minutes of disk reservoir ahead of the playhead, bounded budget, sane eviction.

### Non-negotiables (hard constraints, treat as invariants)
- **N1 — DV transport.** AVPlayer is fed **only** a plain `http://127.0.0.1` URL (or a direct `AVURLAsset`). **Never** an `AVAssetResourceLoaderDelegate` custom scheme. (Fact 1: custom scheme black-screens DV, device-confirmed.)
- **N2 — three-way DV agreement.** For fMP4 DV to light up, all three must agree: loopback server `Content-Type` = `video/mp4`, asset built with `AVURLAssetOverrideMIMETypeKey = video/mp4`, and the **container boxes flow byte-exact** (no remux/repack; `dvcC`/`dvvC` for profile 5, `hvcC`+RPU for profile 7).
- **N3 — serve/origin isolation.** The serve loop **never** contacts origin except for on-demand cache-miss fetch; only `OriginDownloader` opens the persistent session. (Fact 2.)
- **N4 — no reload-on-stall.** Rebuilding the `AVPlayerItem` is the **last** rung of recovery, never the first response to a stall. (Fact 6 / the proven cut root cause.)
- **N5 — binary quality hierarchy.** Full DV (original via loopback) **or** clean H264 HLS SDR (server tone-maps). The HEVC stream-copy / `conservativeCompatibility` path is **forbidden** (Fact 5: dark HDR10, RPU dropped).
- **N6 — Apple-native only.** No third-party media engines, no private playback APIs. (Fact 7.)
- **N7 — one persistent session, bounded parallel windows.** No per-request connections, no byte-at-a-time. (Fact 2 / G9.)
- **N8 — public API preserved verbatim.** The UI seam (below) must not change.

---

## 2. Architecture Overview

Single linear pipeline, one `AVPlayer`, exactly **one branch** in the whole engine (lane selection at load) plus **one mid-stream lane swap**. The cleverness lives in the disk reservoir, not the control flow.

```
        ┌────────────────────────────── ReelFinUI ──────────────────────────────┐
        │  PlayerView ── binds ──▶ engine.player (AVPlayer) + @Observable state   │
        │  (single AVPlayerViewController host; NO surface choice)                │
        └───────────────────────────────┬────────────────────────────────────────┘
                                         │ public API (load/play/seek/…)
        ┌────────────────────────────────▼───────────────────────────────────────┐
        │  PlaybackEngine  (REPLACES PlaybackSessionController; @MainActor @Observable) │
        │  thin orchestrator — owns AVPlayer, active CacheProxySession, sub-controllers│
        │   load → SourceResolver → StartupProbe → LaneController → bind monitors     │
        └──┬──────────┬─────────────┬───────────────┬──────────────┬───────────────┬─┘
           │          │             │               │              │               │
   SourceResolver  StartupProbe  LaneController  ConnectionMonitor PlaybackHealthMonitor SeekController
   (wraps Coord +  (wraps        (THE branch +   (measured Mbps    (recovery ladder,    (coalesced
    DecisionEngine) Preheater)    one swap)       + drain rate)     no reload-on-stall)  serve-fetch)
           │                          │
           │                          ▼
           │              ┌──────── CacheProxySession (NEW; pure composition) ────────┐
           │              │  start(originURL) → http://127.0.0.1 ;  setPlayhead ;       │
           │              │  reservoirSecondsAhead ; stop ; owns CacheBudgetManager     │
           │              └──┬──────────────────┬──────────────────────┬───────────────┘
           │                 │                  │                      │
           ▼          OriginDownloader   MediaGatewayStore      LocalCacheHTTPServer
   (Jellyfin sources) (KEEP: 1 session,  (KEEP store + NEW      (KEEP; uses
                       parallel windows)  range-eviction prim)   LocalMediaGatewayHTTP types)
```

### REUSED (proven, validated — keep with care)
| Component | Files | Note |
|---|---|---|
| `OriginDownloader` | `MediaGateway/OriginDownloader.swift` | KEEP. One keep-alive session, parallel windows, commit-as-you-go, `primeStart()`, `setPlayhead(_:)`, contiguousEnd resume. Only origin toucher. |
| `MediaGatewayStore` (+`+Files`, `Index`, `CacheKey`) | `MediaGateway/MediaGatewayStore*.swift`, `MediaGatewayIndex.swift`, `MediaGatewayCacheKey.swift` | KEEP store; `readAvailablePrefix`, `contiguousEnd`, `coverageEvents`, `availableCapacityBytes`. **ADD** a range-aware eviction primitive (see §4). |
| `LocalCacheHTTPServer` | `MediaGateway/LocalCacheHTTPServer.swift` | KEEP. The DV-safe transport. Depends on `LocalMediaGatewayHTTP.swift` types — keep that file too. |
| `LocalMediaGatewayHTTP.swift` | `MediaGateway/LocalMediaGatewayHTTP.swift` | **KEEP (boundary correction).** Defines `LocalMediaGatewayHTTPRequest` / `…HTTPResponse` used by the server. Rename later to `LocalCacheHTTP*` for clarity, but keep. |
| `PlaybackCoordinator` | `PlaybackCoordinator.swift` | KEEP (slim). Source selection; drop the `.legacyPlaybackCoordinator` self-block + `nativeBridge` branch. |
| `PlaybackDecisionEngine` | `PlaybackDecisionEngine.swift` | KEEP unchanged. Pure route selection. |
| `PlaybackStartupPolicy`, `DirectPlaySessionPolicy` | `PlaybackStartupPolicy.swift`, `DirectPlaySessionPolicy.swift` | KEEP. Per-route buffer rules. |
| `PlaybackStartupPreheater` | `PlaybackStartupPreheater.swift` | KEEP, wrapped by `StartupProbe`. Probe = throughput test = first bytes. Preserve per-platform probe sizing. |
| Skip-segment + track selection | `PlaybackSessionController+SkipSegments.swift`, track-selection code | EXTRACT into new engine before deleting the controller. Working peripherals. |

### NEW
| Type | Responsibility |
|---|---|
| `PlaybackEngine` | Thin `@MainActor @Observable` orchestrator. Replaces the 9315-line controller. Owns the one `AVPlayer`, active `CacheProxySession`, and sub-controllers. Target ≤ 800 lines. Preserves the public API verbatim (§7). |
| `CacheProxySession` | Per-title lifecycle wrapper composing the trinity. `start(originURL) -> localhostURL`, `setPlayhead`, `reservoirSecondsAhead`, `stop()`. Holds depth policy. **Pure composition over kept components — except it owns the new `CacheBudgetManager`.** |
| `CacheBudgetManager` + store range-eviction primitive | NEW. Range-aware eviction (evict-behind-playhead, protect-forward-reservoir, keep 60–90s rewind, evict cold prior-title scopes before throttling fill). **This is real new code** — `trim` cannot do it. |
| `LaneController` | The single branch + the one mid-stream swap. DV-cache lane vs H264-HLS-transcode lane. Predictive downgrade, hysteresis upgrade, anti-flap. Forbids HEVC stream-copy. |
| `ConnectionMonitor` | Single source of truth for measured throughput (preheat seed + sliding window from the downloader session). Exposes `sustainedMbps` **and `reservoirDrainRate`** (the always-available signal that fixes idle-blindness). |
| `PlaybackHealthMonitor` | KVO/notification state machine driving the reload-averse recovery ladder. |
| `SeekController` | Coalesced, tolerance-aware seeking with serve-fetch-first deep resume + re-anchor. |
| `StartupProbe` | Two-phase startup wrapper over the preheater + startup policies. |
| `SourceResolver` | Thin async boundary: `PlaybackCoordinator` + `PlaybackDecisionEngine` → `LaneOptions { originURL, originBitrate, hlsTranscodeURL, tracks }`. |

### DELETED (cruft — Fact 6)
- `NativePlayer/` — `NativePlayerPlaybackController.swift`, `NativePlayerRouteGuard.swift`, `OriginalMediaResolver.swift`.
- `NativeBridge/` — entire directory (15 files: `MatroskaDemuxer`, `FMP4Repackager`, `EBMLParser`, `MP4BoxWriter`, `NativeBridgeSession`, `NativeBridgeResourceLoader`, `DolbyVisionGate`, `HTTPRangeReader`, etc.). Server-side remux replaces it.
- `HLS/` synthetic set — `LocalHLSServer.swift`, `SyntheticHLSSession.swift`, `HLSManifestBuilder.swift`, `HLSSegmentDiskCache.swift`, `CMAFSegmentTimelineBuilder.swift` (fed only NativeBridge).
- `MediaGateway/CacheResourceLoaderDelegate.swift` + `MediaGateway/CachingMediaByteSource.swift` — the `reelfin-cache://` DV black-screener. (Only a comment references them — safe.)
- Legacy gateway cluster superseded by `CacheProxySession`: `LocalMediaGatewaySession.swift`, `LocalMediaGatewayServer.swift`, `LocalMediaGatewayPrefetcher.swift`, `LocalMediaGatewayRoutePolicy.swift`, `LocalMediaGatewayURLPolicy.swift`, `LocalMediaGatewayHTTPURLResponse.swift`, `PlaybackMediaCachePolicy.swift`. **NOT `LocalMediaGatewayHTTP.swift`** (kept — see boundary correction).
- `Shared/NativePlayerConfig.swift` + `NativePlayerRuntimeDefaults`.
- The `PlaybackSessionController` god object (9315 lines) + its native-bypass-to-coordinator duplication.
- `ReelFinUI` `NativePlayerView` (sample-buffer branch) — collapse `PlayerView` to a single AVKit host.

---

## 3. End-to-End Playback Flow

```
load(item, startTimeTicks, autoPlay)
  │
  ├─ 1. SourceResolver.resolve(item)
  │        → LaneOptions { originURL, originBitrate(~26Mbps), hlsTranscodeURL(offset), tracks, dvProfile }
  │
  ├─ 2. StartupProbe (Phase A): short range fetch on the persistent keep-alive session.
  │        • bytes are committed to the store → they ARE the first frame-0 bytes (never wasted)
  │        • timed → ConnectionMonitor.seed(measuredMbps)
  │
  ├─ 3. LaneController.pickStartLane:
  │        measuredMbps * 0.7 ≥ originBitrate  → DV lane
  │        else                                 → degraded (SDR HLS) lane   (start-then-stutter avoided)
  │
  ├─ 4a. DV LANE:
  │        CacheProxySession.start(originURL):
  │          OriginDownloader.primeStart() + setPlayhead(startOffset)   // tail moov + head + forward windows
  │          LocalCacheHTTPServer.start() → http://127.0.0.1:port/token
  │        asset = AVURLAsset(url: localhostURL, options:[AVURLAssetOverrideMIMETypeKey: "video/mp4"])  // N2
  │        player.replaceCurrentItem(AVPlayerItem(asset))
  │
  ├─ 4b. DEGRADED LANE:
  │        player.replaceCurrentItem(AVPlayerItem(url: hlsTranscodeURL))   // also via a small cache proxy — see §4 note
  │
  ├─ 5. Apply startup policy:
  │        automaticallyWaitsToMinimizeStalling = true
  │        preferredForwardBufferDuration = 0                      // fast first frame
  │        canUseNetworkResourcesForLiveStreamingWhilePaused = true
  │        preferredPeakBitRate set ONLY on the HLS lane
  │
  ├─ 6. Phase A first frame: server serves probe bytes on hit / fetchRangeOnDemand on miss.
  │        Gate releases on likely-to-keep-up vs LOW threshold.  → ≤1.5s
  │
  ├─ 7. Phase B (concurrent, post-.playing):
  │        step preferredForwardBufferDuration → 45–60s (RAM)
  │        downloader fills disk reservoir → 180s (grow to 300–360s on headroom)
  │        ConnectionMonitor samples sustainedMbps + reservoirDrainRate continuously
  │
  ├─ 8. Steady state:
  │        serve loop drains disk (readAvailablePrefix), woken by coverageEvents
  │        downloader follows furthest published playhead
  │        CacheBudgetManager trims behind playhead, keeps rewind window
  │        LaneController watches drain vs fill for predictive swaps
  │
  ├─ seek(to:): SeekController coalesces → cache hit instant / miss serve-fetch target range first,
  │             setPlayhead(newOffset), cancel far windows, rebuild reservoir forward, keep rewind.
  │
  └─ stop(): capture currentTime → PlaybackProgress; downloader.stop; server.stop; CacheBudgetManager.trim.
```

**Mid-stream adapt/upgrade/downgrade** — see §4 (downgrade) and §6 (upgrade). Both happen *behind the live buffer* so quality changes but motion never stops.

---

## 4. Never-Cut Strategy (exact rules)

Three independent layers. The first two are proven; the third replaces the proven cut-causer.

### Layer 1 — Disk reservoir (primary; Fact 3)
- Depth measured in **seconds of playback**, not bytes. Steady target **180s**, grow to **300–360s** on a fast link with disk headroom.
- The RAM forward buffer (`preferredForwardBufferDuration` ≤ 45–60s) is the *playback* buffer; the **disk** reservoir is the *dropout* reservoir. Never try to win this with `preferredForwardBufferDuration` — it jetsam-caps ~60–120s and cannot hold minutes.
- **Rule:** any total link dropout **shorter than the reservoir depth is fully invisible** — the player drains disk while the downloader retries.

### Layer 2 — Serve/origin isolation + resumable downloader (Fact 2; N3)
- Only `OriginDownloader` touches origin: one persistent session, bounded parallel windows (3–6), commit-as-you-go ≥256KB.
- A `-1001`/`-1005`/reset loses only the uncommitted window tail and resumes from `store.contiguousEnd`. Retry is **infinite with bounded exponential backoff**.
- The serve loop calls origin only on a *true cache miss* (`fetchRangeOnDemand`), never for steady streaming.

### Layer 3 — Reload-averse recovery ladder (replaces reload-on-stall; N4)
Driven by `PlaybackHealthMonitor` (state machine over `timeControlStatus` + `reasonForWaitingToPlay`, KVO on `isPlaybackBufferEmpty` / `isPlaybackLikelyToKeepUp` / `loadedTimeRanges`, + `AVPlayerItemPlaybackStalled` / failed-to-play-to-end):

1. **Wait** — observe `reasonForWaitingToPlay`; the disk buffer is likely refilling.
2. **Nudge** — widen the downloader's disk lead / re-anchor playhead.
3. **Absorbed-by-design** — do nothing; let AVPlayer drain disk and self-recover.
4. **Downgrade** (only if reservoir is genuinely draining and link is down) — `LaneController` collapse to SDR at `currentTime` (see below).
5. **Last resort** — rebuild `AVPlayerItem` at exact `currentTime()` with a pre-warmed cache so the rebuild is instant. **Never rebuild on every stall.**

### Predictive downgrade (connection-verified routing)
- **Trigger on predicted starvation, not empty buffer.** Condition: `ConnectionMonitor.sustainedMbps` has held below sustained-source-bitrate long enough that **`reservoirDrainRate > fillRate` and projected-to-empty within the calibrated transcode spin-up lead `N`**. Fire while ≥ `N` seconds of runway remain.
- Sequence (clean downgrade): (1) ask Jellyfin to open the H264 transcode at the current playhead; (2) keep playing DV from the still-draining reservoir; (3) swap to the transcode lane only once it has its own startable buffer at a segment/keyframe boundary; (4) the reservoir cushion absorbs spin-up. **Result: quality drop, not freeze.**
- **`N` is calibrated on-device** (measured Jellyfin transcode-start-to-first-segment) and the downgrade threshold is **coupled to it** and biased to fire early.

### Idle-blindness fix (grafted improvement)
When the reservoir is full the downloader sleeps and throughput samples stop. `reservoirDrainRate` is the **always-available primary signal** — drain rate is observable even with no active fetches, so a link collapse during idle is detectable the moment fill must resume. A lightweight periodic keep-alive probe is a secondary signal only.

### Degraded-lane dropout immunity (grafted hole-closure)
The marginal link that forced the downgrade is exactly when cuts are most likely — so the **degraded H264-HLS lane is also routed through a `CacheProxySession`** (small disk buffer, e.g. 30–60s), not played raw. The fallback lane keeps real dropout immunity instead of being the most-exposed lane.

### Eviction rules (NEW — `trim` cannot do this)
- Bounded disk budget (a few GB; current default 8GB LRU is whole-key).
- **Evict behind the playhead first** (LRU on already-played ranges).
- **Keep a 60–90s rewind window** behind the playhead for instant back-seek.
- **Never evict ahead-of-playhead committed reservoir** to make room for further-ahead fetches — the runway in front is sacred (`protectedKeys` + range guard).
- On a new title, **evict cold prior-title scopes before throttling the active fill.**
- Cap reservoir-seconds against `availableCapacityBytes()`.

### Never-permanent-freeze (G6; hard escape)
The ladder cannot terminate on a frozen frame. Bounded backoff with a **hard ceiling on total unreachable elapsed time** → if origin is genuinely gone, surface an explicit paused/error state (`playbackErrorMessage`), never a silent hang.

---

## 5. DV / HDR Strategy

**Preserve by construction (N1, N2; Fact 1).** The DV lane *always* feeds AVPlayer a plain `http://127.0.0.1` URL backed by the cache proxy, never a custom scheme. The clean engine has **no resource-loader path at all**, so the black-screen failure mode is structurally removed. Why localhost works and custom scheme fails: over HTTP/file AVFoundation parses the DV config boxes (`dvcC`/`dvvC` profile 5, `hvcC`+RPU profile 7), enters DV display mode, and flows per-frame RPU metadata to the compositor; under `AVAssetResourceLoaderDelegate` you take over content typing/loading and that DV decode-config + RPU-to-display wiring is never established.

**Three-way agreement enforced in `CacheProxySession`:** server `Content-Type: video/mp4`, `AVURLAssetOverrideMIMETypeKey = video/mp4`, byte-exact container. Profiles handled: DV 5 / 7 / 8.1, HDR10 (static metadata), HLG (self-describing) — all flow because the bytes are unmodified.

**Graceful drop is binary and intentional (N5; Fact 5).** When sustained throughput < ~26 Mbps source floor, true 4K DV is physically impossible → drop to **Jellyfin H264 HLS transcode** (`/master.m3u8`, `VideoCodec=h264`), which server-tone-maps HDR→SDR = clean watchable SDR.

**Forbidden:** the `conservativeCompatibility` HEVC stream-copy path — it carries PQ pixels but drops the RPU, rendering dark crushed HDR10 with no re-grade. **The hierarchy is full-DV or clean-SDR, never a broken dark in-between.** Encode this as a test invariant (a unit test asserts `LaneController` never selects HEVC stream-copy).

**Optional middle rung:** if Jellyfin can serve a lower-bitrate stream that *still carries valid DV* through the loopback, prefer it above SDR. Absent that, SDR transcode is the floor.

**Runtime proof:** `proofSnapshot.dolbyVisionActive` must read true on the DV lane; CI carries an on-device "DV actually renders" assertion against a known profile-5 **and** profile-7 title through the localhost path (HDR10/HLG validated as a distinct path, not lumped with DV).

---

## 6. Fluidity / Speed Strategy

**Fast first frame — decouple "enough to start" from "enough to be safe."**
- **Phase A:** fetch only moov/init + minimum media for frame 0. The **preheat probe bytes ARE the first bytes** (zero extra latency). Release the gate on `isPlaybackLikelyToKeepUp` vs a **low** threshold with `preferredForwardBufferDuration = 0` and `automaticallyWaitsToMinimizeStalling = true`. Targets: first frame ≤ 1.5s (ceiling 2.5s); deep-seek/resume ≤ 4s (proven 3.8s on-demand serve-fetch); cache-hit seek ≤ 0.5s.

**Smooth steady state.**
- The instant frame 0 paints, Phase B runs the downloader full-throttle: build the 45–60s RAM buffer (step `preferredForwardBufferDuration` up — AVPlayer honored 51s, Fact 4) then the 180s+ disk reservoir, all behind the already-watching user.
- `canUseNetworkResourcesForLiveStreamingWhilePaused = true` keeps the reservoir filling while paused.
- Serve loop woken by `coverageEvents` — never busy-spins, never starves while bytes arrive.

**Cold-start hardening (grafted; verified real failure).** Cold first-range latency has been observed at ~14.6s (CF/server warming), and a preroll on a not-ready item once crashed the device. `StartupProbe` must: never preroll/seek a not-yet-ready item; treat a slow first range as a *cold-start* state with its own timeout + retry (not the steady-state budget); and keep the per-platform preheat probe sizes (tvOS differs).

**Throughput is measured, not guessed.** From the real keep-alive session sliding window (not AVPlayer's opaque heuristics), driving asymmetric adaptation: **downgrade eagerly** (protect fluidity), **upgrade conservatively** with hysteresis.

**Upgrade (degraded → DV) without freeze.** Require sustained ≥ 1.3× source bitrate for a 20–30s hold-down on a healthy disk lead. Pre-fill the DV reservoir in the background while still showing the transcode; switch only once DV has a safe buffer. Anti-flap: minimum dwell per lane, exponential cooldown on oscillation, longer SDR floor if DV can't hold twice.

---

## 7. Public Engine API (the seam the app binds to)

The new `PlaybackEngine` **must** preserve this surface exactly (verified against the current controller). During migration, `typealias PlaybackSessionController = PlaybackEngine` so existing call sites compile unchanged.

```swift
@MainActor @Observable
public final class PlaybackEngine {
    public init(apiClient:, decisionEngine:, …)            // same dependencies

    // Playback control
    public func load(item:, startTimeTicks:, autoPlay:)     // async
    public func play()
    public func pause()
    public func togglePlayback()
    public func seek(to seconds: Double)
    public func seek(by seconds: Double)
    public func stop() -> PlaybackProgress?

    // Track selection
    public func selectAudioTrack(id: String)
    public func selectSubtitleTrack(id: String?)

    // Skip segments
    public func skipCurrentSegment()

    // Direct player access (UI host binds this)
    public var player: AVPlayer { get }

    // Observable state (UI re-renders on change)
    public var transportState: PlaybackTransportState        // tracks, skip suggestions, trickplay
    public var proofSnapshot: PlaybackProofSnapshot          // diagnostics — see below
    public var playbackErrorMessage: String?
}
```

**`PlaybackProofSnapshot` fields are load-bearing for the UI** (verified `PlaybackSessionController.swift:82–132`) and must be populated by the new engine: `dolbyVisionActive`, `hdrTransfer`, `codecFourCC`, `bitDepth`, `playbackMethod`, `sourceBitrate`, `observedBitrate`, `dvProfile`, `videoRangeType`, `preservesOriginalVideo`, `preservesDolbyVision`, `startupClass`, `fallbackOccurred`, `fallbackReason`, `playerItemStatus`, `timeToFirstFrameMs`, `stallCount`, etc. Map them to the new lane/health/connection state.

**Semantic preservation, not just signatures:** a Phase-0 contract test asserts signatures; additionally snapshot observable timing/ordering the UI depends on (e.g. when `transportState.availableAudioTracks` populates relative to `playerItemStatus == .readyToPlay`). Track-selection continuity across a lane swap must be handled explicitly — DV-original and H264-transcode tracks have different indices, so map by language/codec identity and re-apply user selection after a swap.

`updateNativePlayerPlaybackTime`, `markAVKitReadyForDisplay`, `exportNativeBridgeDebugBundle`, and the `nativePlayerPathActive` / `isNativePlayerActive` flags are native-path vestiges — keep as no-op/constant shims during migration to avoid breaking the seam, then remove from the UI in the cutover phase.

---

## 8. Ordered Implementation Phases

Each phase is independently testable, and each names the **offline test that proves it** — reusing and extending the existing harness (`MockOriginalMediaProtocol` is a `URLProtocol` with per-range delay injection; `MediaGatewayStoreTests`, `LocalMediaGatewayServerTests`, `MediaGatewayIndexTests`). **No device round-trips to iterate** — device runs are confirmation-only at phase ends.

**Extend the harness first:** add to `MockOriginalMediaProtocol` the ability to inject mid-stream `-1005` reset, `-1001` timeout, total-dropout-for-N-seconds, and a throttled bytes/sec cap — so every never-cut and adaptation claim is provable offline.

---

**Phase 0 — Lock the contract + safety net.**
- Snapshot the exact public API + every `proofSnapshot` field as a compile-time contract test.
- Add green regression tests asserting the trinity's proven behaviors still hold: byte-exact delivery, zero-stall-through-injected-reset, 3.8s-class deep-resume.
- On-device: confirm **DV actually renders** through `LocalCacheHTTPServer` localhost with a hardcoded profile-5 and profile-7 URL — this retires the single biggest unproven assumption before any deletion.
- **Offline proof:** contract test compiles + passes; store/server tests green; harness extended.

**Phase 1 — Boundary correction inside `MediaGateway/`.**
- Rename `LocalMediaGatewayHTTP.swift` types to `LocalCacheHTTP*` (or explicitly retain), so the kept server has no name overlap with the to-be-deleted legacy cluster.
- Confirm `LocalCacheHTTPServer` compiles with the legacy session/server/prefetcher/policy files removed from the build (the comment-only references to `CacheResourceLoaderDelegate` are fine).
- **Offline proof:** package builds with only the kept `MediaGateway/` files; `LocalMediaGatewayServerTests` adapted to the kept server stay green.

**Phase 2 — `CacheProxySession` over the trinity + NEW range-eviction.**
- Wire `OriginDownloader` + `MediaGatewayStore` + `LocalCacheHTTPServer`; expose `start/setPlayhead/reservoirSecondsAhead/stop`.
- Implement `CacheBudgetManager` + the new `MediaGatewayStore` range-eviction primitive (evict-behind-playhead, protect-forward, 60–90s rewind).
- **Offline proof:** dropout-immunity test (inject total dropout < reservoir → zero stalls); re-anchor-on-seek test; **eviction test** under disk-full + title-switch asserting ahead-of-playhead committed ranges are never evicted.

**Phase 3 — `StartupProbe` (two-phase) + DV-lane-only `PlaybackEngine`.**
- `load → SourceResolver → preheat → DV lane only` through `CacheProxySession` with `AVURLAssetOverrideMIMETypeKey`. No degraded path yet.
- **Offline proof:** first-frame gate releases on probe bytes against a throttled mock; reservoir grows to 180s; cold-start path (14.6s-class first range) handled without preroll-on-not-ready.

**Phase 4 — `PlaybackHealthMonitor` + recovery ladder.**
- Port the KVO/notification state machine, strip native branches, implement the reload-averse ladder. Remove all reload-on-stall code.
- **Offline proof:** inject dropouts both shorter and longer than the reservoir → shorter = zero visible stall and **no item rebuild**; longer = honest paused/error state, never a frozen frame (verify the hard ceiling escape).

**Phase 5 — `ConnectionMonitor` + `LaneController` (degraded lane + adaptation).**
- Sliding-window `sustainedMbps` + `reservoirDrainRate`; predictive behind-the-buffer downgrade to H264 HLS (also via a small cache proxy); hysteresis upgrade; anti-flap. Forbid HEVC stream-copy (test invariant).
- Calibrate transcode spin-up `N` (the one device measurement), feed into the downgrade trigger.
- **Offline proof:** replay a 10–232 Mbps flapping trace → lane swaps occur with the reservoir non-empty (no stall at the seam); flap test asserts dwell/cooldown prevent oscillation; assertion that the HEVC path is never chosen.

**Phase 6 — `SeekController` + UI cutover.**
- Coalesced tolerance-aware seeking with serve-fetch-first deep resume + re-anchor + rewind window.
- Replace `PlayerView`'s native/sample-buffer branch with a single `AVPlayerViewController` host bound to `engine.player`; remove surface choice and native vestige flags from the UI.
- **Offline proof:** cache-hit seek ≤ 0.5s; cache-miss deep seek serve-fetches target range first; track selection preserved across a simulated lane swap.

**Phase 7 — Delete the cruft.**
- Remove `NativePlayer/`, `NativeBridge/`, synthetic `HLS/`, `CacheResourceLoaderDelegate` + `CachingMediaByteSource`, the legacy gateway cluster (NOT `LocalMediaGatewayHTTP.swift`), `NativePlayerConfig`/`RuntimeDefaults`, and the `PlaybackSessionController` god object.
- Regenerate `project.yml` → `xcodegen generate`; run the full test + build matrix on iPhone 17 / iOS 26.2.
- **Offline proof:** full suite green after deletion; `typealias` shim removed; no dangling references.

**Phase 8 — Tune + harden (device confirmation).**
- Calibrate reservoir depth vs jetsam, per-platform probe sizes, eviction budget, lane hysteresis, and `N` against real 10–232 Mbps + total-dropout conditions. Validate every G1–G10 guarantee on-device.

---

## 9. What to Delete, and Migration / Rollback Safety

### Delete list (with boundary)
See §2 DELETED. **Critical boundary:** delete the legacy gateway *session/server/prefetcher/policy/URL-policy* files, but **KEEP `LocalMediaGatewayHTTP.swift`** (it defines the request/response types the kept server uses) and **KEEP `MediaGatewayStore` + index + cache-key**. Do the rename in Phase 1 *before* the bulk delete in Phase 7 so the kept server never loses its types.

### Migration safety
- **`typealias PlaybackSessionController = PlaybackEngine`** keeps every UI call site and `ReelFinDependencies.makePlaybackSession` compiling through the whole migration.
- **Extract working peripherals (skip segments, track selection, proof snapshot population, warmup/health) into the new engine *before* deleting the controller** — this is where clean rebuilds usually regress; do it under the Phase-0 contract test.
- Native-path API vestiges (`updateNativePlayerPlaybackTime`, `markAVKitReadyForDisplay`, `exportNativeBridgeDebugBundle`, `nativePlayerPathActive`) become no-op/constant shims until the Phase-6 UI cutover removes their call sites.
- All NEW behavior is gated behind its own type, not interleaved into kept components — `CacheProxySession`/`LaneController`/etc. compose over the trinity, keeping the proven transport untouched (except the explicitly-NEW range eviction).

### Rollback safety
- The branch is `feat/custom-player-rebuild`; `main` retains the working engine.
- Phases 0–6 are additive (new types alongside the old controller, behind the typealias). The old controller is not deleted until Phase 7 — so any phase can be reverted by dropping its commits without resurrecting deleted code.
- A feature flag (`useCustomPlayerEngine`) can route `makePlaybackSession` to the new engine vs the legacy controller until Phase 7, giving an instant runtime rollback during on-device validation.
- The Phase-0 DV-renders assertion and the dropout/no-reload offline tests are the regression gates: no phase merges unless they stay green.

---

### Two design tensions resolved explicitly
1. **Memory vs disk depth (Fact 3 vs 4):** the 180s+ resilience lives on **disk**, fed to AVPlayer just-in-time through the loopback. `preferredForwardBufferDuration` is capped at 45–60s and never asked to hold minutes.
2. **Downgrade lead time vs reservoir depth:** the reservoir must cover transcode spin-up `N`; the downgrade trigger fires while ≥ `N` seconds remain, with `N` measured on-device and the threshold biased to fire early. The down-transition is the one place a brief visible quality drop is acceptable — bias hard toward firing early so a hard dropout still has SDR lead time.

**One-line contract:** *Fast to first frame, deep on disk, honest about quality — it starts in under ~1.5s, holds minutes of buffer on disk so dropouts are invisible, renders true Dolby Vision whenever the link can carry it, drops to clean watchable SDR the moment it can't (switching lanes behind the buffer so picture quality changes but motion never stops), and never ends on a frozen frame.*
