# Playback Architecture (Current — v0.6)

This document describes the **real, shipping** playback stack in ReelFin.
It is kept in sync with the runtime; do not document aspirational architecture here.

---

## Core components

| Component | Role |
|---|---|
| `PlaybackSessionController` | Main orchestrator: lifecycle, watchdogs, fallback, diagnostics |
| `PlaybackCoordinator` | Resolves a `PlaybackAssetSelection` from Jellyfin API sources |
| `PlaybackDecisionEngine` | Chooses route (DirectPlay / Remux / Transcode) from source list |
| `CapabilityEngine` | Assigns a planning lane (nativeDirectPlay / jitRepackageHLS / surgicalFallback) |
| `AudioCompatibilitySelector` | Scores and selects the best audio track (language-aware) |
| `AudioTrackLanguageNormalizer` | Normalises ISO 639-1/2 and BCP-47 language tags for comparison |
| `SubtitleCompatibilityPolicy` | Guards bitmap subtitles in strict HDR mode |
| `HLSVariantSelector` | Pins the best HLS variant after master playlist fetch |
| `NativeBridge` (disabled) | Local MKV → fMP4 repackager — kept behind a feature flag, not active in shipping builds |

### Platform-specific components

| Component | Platform | Role |
|---|---|---|
| `TVRootShellView` / `TVTopNavigationBar` | tvOS | Focus-driven navigation shell with Liquid Glass |
| `TVLoginView` | tvOS | Quick Connect + password login |
| `PlaybackWarmupManager` | tvOS | Pre-resolves playback plan on detail page open to hide latency |

---

## Decision flow

```
load(item:)
  │
  ├─ read ServerConfiguration (playbackPolicy, allowSDRFallback,
  │                             preferredAudioLanguage, preferredSubtitleLanguage)
  │
  ├─ PlaybackCoordinator.resolvePlayback()
  │    └─ PlaybackDecisionEngine.decide()
  │         1. rawDirectPlayDecision   — MP4/MOV/M4V only
  │         2. decisionFromPlan        — CapabilityEngine result
  │            · nativeDirectPlay lane
  │            · jitRepackageHLS lane  → server transcode (NativeBridge disabled)
  │            · surgicalFallback lane → server transcode
  │         3. directPlayCandidate     — catch-all direct play
  │         4. nativeBridgeCandidate   — DISABLED (isNativeBridgeEnabled = false)
  │         5. remuxCandidate
  │         6. transcodeCandidate
  │         7. fallbackTranscode       — last resort
  │
  ├─ AudioCompatibilitySelector (language-aware, see §Audio selection)
  ├─ pinPreferredVariantIfNeeded      — HLS variant pinning
  ├─ stabilizeInitialSelectionIfNeeded
  ├─ upgradeRiskyInitialSelectionIfNeeded
  │
  ├─ prepareAndLoadSelection()
  │    ├─ audio track initial selection (stored in selectedAudioTrackID)
  │    ├─ subtitle auto-selection      (stored in selectedSubtitleTrackID)
  │    ├─ HDR/DV expectation log       (emitDynamicRangeExpectationLog)
  │    └─ AVURLAsset + AVPlayerItem creation
  │
  └─ startup watchdog (6–14 s depending on profile)
       └─ on expiry → attemptRecovery() → next TranscodeURLProfile
```

---

## Playback routes

| Route | When chosen | Notes |
|---|---|---|
| `DirectPlay` | MP4/MOV/M4V + native codecs | Fastest path; progressive `static=true` URL preferred |
| `Remux` (DirectStream) | HLS stream URL from Jellyfin | Good for HLS-capable sources |
| `Transcode` | MKV, incompatible codecs, fallback | Profile determines quality vs. compatibility |
| `NativeBridge` | **DISABLED** | Local MKV→fMP4; ready behind flag, not active |

**MKV files always go through `Transcode`.** There is no MKV direct-play path.

---

## Transcode profiles

| Profile | Key params | Use case |
|---|---|---|
| `serverDefault` | Keep `AllowVideoStreamCopy=true` when safe | First attempt for unknown sources |
| `appleOptimizedHEVC` | `VideoCodec=hevc`, `AllowVideoStreamCopy=false`, `Container=fmp4` | MKV HEVC / HDR — clean server-side HEVC transcode |
| `conservativeCompatibility` | Source codec kept, normalised `SegmentLength/MinSegments` | Middle ground for uncertain hardware |
| `forceH264Transcode` | `VideoCodec=h264`, `RequireAvc=true`, `Container=ts` | Reliable SDR output via H.264 MPEG-TS |

**Recovery cascade** (default `auto` policy, 2 recovery attempts):

*iOS:*
```
serverDefault → appleOptimizedHEVC → conservativeCompatibility → forceH264Transcode
```

*tvOS:*
```
serverDefault → appleOptimizedHEVC → forceH264Transcode
```

> **tvOS note:** `conservativeCompatibility` is skipped in the tvOS recovery chain.
> All MKV transcode paths on tvOS begin with `forceH264Transcode` directly
> (see §tvOS playback below).

Once `forceH264Transcode` is used, no further fallback is attempted.

Profile choices are persisted per item ID so subsequent loads skip known-bad profiles.

---

## Audio selection algorithm

Selection is deterministic and uses a **layered scoring model**.
Higher tiers override lower tiers unconditionally.

| Tier | Condition | Score |
|---|---|---|
| 1 | Exact preferred-language match (`ServerConfiguration.preferredAudioLanguage`) | +100 000 |
| 2 | Prefix / regional preferred-language match (`fr` matches `fr-CA`) | +50 000 |
| 3 | Track marked `isDefault` by source metadata | +10 000 |
| 4 | Natively playable codec (AAC +500, EAC3 +400, AC3 +300) | +200–500 |
| 4 | Codec requiring server transcoding on native path (TrueHD, DTS) | −50 000 |
| 5 | Stream order tie-breaker (earlier = smaller negative) | −streamOrder |

**Key consequences:**

- French AC-3 (default) **always beats** English E-AC-3 Atmos (non-default) even without
  an explicit language preference, because the default bonus (10 000) far exceeds the
  codec gap (400 − 300 = 100).
- With `preferredAudioLanguage = "fr"`, French wins even if it is not the default track.
- TrueHD and DTS are **penalised** on the native AVPlayer path because AVFoundation
  cannot decode them. They can only win if they are literally the only track available.
- Language tags are normalised via `AudioTrackLanguageNormalizer`:
  `fre`, `fra`, `fr-FR`, `fr-CA` all match a preference of `"fr"`.

---

## Subtitle selection algorithm

### Auto-selection at startup

The following logic runs once when the `AVPlayerItem` reaches `.readyToPlay`:

1. If any track is marked `isDefault` (and not a blocked bitmap type in strict mode) → select it.
2. Otherwise, if there is a **forced** subtitle track matching `preferredSubtitleLanguage` → select it.
3. Otherwise, if there is a **forced** subtitle track matching the selected audio track's language → select it (handles foreign-language inserts without user action).
4. Otherwise → no subtitle is auto-selected; user must choose manually.

### Strict mode guard

When `playbackQualityMode == .strictQuality` and the source is HDR/DV:
PGS and VobSub (bitmap) subtitles are blocked because selecting them forces a
full server-side transcode that destroys HDR metadata.
Text subtitles (SRT, ASS) are always allowed.

### Runtime switching

User selection is applied via `selectSubtitleTrack(id:)` which uses
`PlaybackTrackMatcher` to fuzzy-map the Jellyfin track to an `AVMediaSelectionOption`.

---

## Dynamic range / HDR policy

### Source classification

`MediaSource.isLikelyHDRorDV` returns `true` when any of:
- `videoBitDepth >= 10`
- `videoRange` contains "hdr", "dolby", "vision", "pq", "hlg"
- `videoRangeType` contains "dovi", "hdr10", "hlg"
- `dvProfile > 0`
- `hdr10PlusPresentFlag == true`
- video codec is `dvhe` or `dvh1`

### Expected output per route

| Source | Route | Expected output |
|---|---|---|
| DV Profile 8.1 | DirectPlay (MP4/MOV) | **Dolby Vision** |
| DV Profile 8.1 | Transcode fMP4 HEVC | **HDR10** (DV SEI not reliably preserved) |
| DV Profile 8.1 | Transcode TS H.264 | **SDR** (all HDR metadata lost) |
| HDR10 | Transcode fMP4 HEVC | **HDR10** (static metadata preserved) |
| HDR10+ | Any transcode | **HDR10** (dynamic HDR10+ metadata not carried) |
| HDR10 | Transcode TS | **SDR** (TS cannot carry HDR10 boxes) |

The startup log emits an explicit `HDR expectation:` line before the AVURLAsset
is created. If DV will be downgraded to HDR10, a `HDR downgrade:` warning is logged.

### Strict quality mode

Activated when `playbackPolicy == .originalLockHDRDV` or
(`source.isLikelyHDRorDV && allowSDRFallback == false`).

In strict mode:
- SDR HLS variants are rejected
- H.264 transcode variants are rejected
- TS container is rejected (no HDR boxes)
- PGS/VobSub subtitles are blocked
- Recovery is limited to 1 attempt (no H.264 fallback)

---

## tvOS playback

### Device profile

On tvOS, `PlaybackInfoOptions.tvOSOptimized()` is selected automatically via `#if os(tvOS)` in `PlaybackCoordinator.playbackOptions()`. The profile tells Jellyfin:

- **DirectPlay**: mp4/m4v/mov with HEVC/H264/DV + AAC/AC3/EAC3/ALAC/FLAC
- **Transcode**: HLS MPEG-TS H.264 (not fMP4 — see below)

### Why fMP4 HLS is disabled for MKV on tvOS

Jellyfin does **not** produce real fMP4 segments when `SegmentContainer=fmp4` is requested
for MKV remux/transcode. It serves raw MPEG-TS bytes (starting with `0x47` sync byte) despite
the `.fmp4` file extension and `hvc1.…` codec signaling in the master playlist.

Apple AVPlayer requires ISO BMFF fMP4 with a `#EXT-X-MAP` init segment for HEVC HLS (CMAF).
Without it, AVPlayer reaches `readyToPlay` status but never decodes a video frame — the decoded-frame
watchdog fires and recovery begins.

**Consequence:** all MKV files on tvOS use `forceH264Transcode` directly.

| Source | tvOS route | Output |
|---|---|---|
| MP4 / MOV / M4V — compatible codecs | DirectPlay | Native quality |
| MKV (any codec) | H.264 HLS TS | SDR H.264 |
| MOV / MP4 — incompatible codec | H.264 HLS TS | SDR H.264 |

### HLS variant selection on tvOS

`HLSVariantSelector` uses **codec rank as the primary sort key** on tvOS (vs. resolution on iOS).
This ensures a Dolby Vision or HDR10 variant is preferred over a higher-resolution SDR variant
when the source already has richer metadata — more relevant once fMP4 HEVC is supported.

### Subtitle deferred selection

External subtitle tracks (SRT/ASS) are not applied at `readyToPlay`. They are deferred until
after the **first decoded video frame** to prevent the HLS reload (player item replacement)
from interfering with startup decoding.

---

## Startup state machine

Simplified observable states:

```
idle → load() called
  → resolving plan (PlaybackCoordinator)
  → pinning variant (HLSVariantSelector)
  → creating AVURLAsset + AVPlayerItem
  → playerItem.status == .unknown
  → playerItem.status == .readyToPlay
      → initial audio selection applied
      → embedded subtitle applied (if auto-selected)
      → external subtitle deferred until first frame (see §tvOS playback)
      → startup watchdog started
  → first video frame decoded (hasDecodedVideoFrame = true)
  → playing

  ─ on watchdog expiry / decoder stall / startup failure ─
  → attemptRecovery() with next TranscodeURLProfile
  → [repeat up to maxRecoveryAttempts times]
  → terminal failure → playbackErrorMessage set
```

### Watchdog timeouts

| Profile | Standard timeout | Extension if readyToPlay but no frame |
|---|---|---|
| `serverDefault` | 6–8 s (3 s for HEVC stream-copy) | +8 s |
| `appleOptimizedHEVC` | 10–14 s (14 s for DV sources) | +8 s |
| `conservativeCompatibility` | 8–12 s (12 s for DV sources) | +8 s |
| `forceH264Transcode` | 30 s | +8 s |

---

## NativeBridge status

The NativeBridge pipeline (local MKV → fMP4 repackager) exists in the codebase
and is architecturally sound, but is **disabled in production** via:

```swift
private static var isNativeBridgeEnabled: Bool { return false }
```

It will not be enabled until:
1. The subtitle pipeline (SRT → WebVTT sidecar injection) is complete.
2. The DV profile detection from CodecPrivate (RPU NAL type 62) is verified.
3. The edit-list (`elst`) handling for B-frame DTS/PTS offsets is implemented.
4. The integration test suite covers full demux → repackage → AVPlayer playback.

**Do not enable NativeBridge in shipping code without completing the above.**

---

## Diagnostics

Every major session decision is logged with structured fields:

| Log category | What it answers |
|---|---|
| `Playback selected method=… container=… video=… audio=… profile=…` | Which route, codec, profile |
| `Audio selected: '…' lang='…' codec=… reason=[…]` | Why this audio track was chosen |
| `Subtitle auto-selected: '…' lang='…' default=…` | Why this subtitle was auto-selected (or no log if none) |
| `HDR expectation: expected='…' source=… route=… reason='…'` | Expected dynamic range output |
| `HDR downgrade:` warning | DV source will play as HDR10 on this route |
| `HDR10+: dynamic HDR metadata… not preserved` | HDR10+ present but dropped |
| `[NB-DIAG] avplayeritem.status — status=…` | AVPlayerItem state transitions |
| `Playback watchdog fired` | Which watchdog triggered recovery |

Use `AppLog.playback` for the main pipeline and `AppLog.nativeBridge` for the local bridge.

---

## Known limitations

1. **MKV direct play is not supported.** MKV files always route through server-side transcode.
2. **tvOS MKV transcode is always H.264 SDR.** Jellyfin does not produce real fMP4 segments for HEVC HLS; H.264 MPEG-TS is the only reliable transcode output on tvOS.
3. **DV preservation through Jellyfin HLS transcoding is not guaranteed.** Expect HDR10 on iOS transcode path, SDR on tvOS transcode path.
4. **HDR10+ dynamic metadata is not preserved** on any server-side path.
5. **TrueHD / DTS require server-side audio transcoding.** They cannot play natively via AVFoundation.
6. **PGS/VobSub subtitles cannot be used in strict HDR mode** without forcing a destructive SDR transcode.
7. **No mid-session HLS adaptation by ReelFin.** AVPlayer handles adaptive bitrate internally.
8. **NativeBridge subtitle pipeline is incomplete.** SRT/ASS subtitle sidecar injection is not yet wired up.

---

## Testing

Target the relevant suites when modifying playback decisions or fallback policies:

```sh
# All playback decision tests (fast, no network)
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:PlaybackEngineTests/PlaybackPolicyTests \
  -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests \
  -only-testing:PlaybackEngineTests/CapabilityEngineTests

# NativeBridge unit tests
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:PlaybackEngineTests/NativeBridgeCoreTests
```

Maintain or extend tests when touching:
- `AudioCompatibilitySelector` — add cases for language/default/codec interaction
- `PlaybackDecisionEngine.decide()` — add cases for new container/codec combinations
- `HLSVariantSelector` — add cases if VIDEO-RANGE or SUPPLEMENTAL-CODECS parsing changes
- Fallback profile cascade — always verify `FallbackOrderIsDeterministic` and `FallbackOrderNeverRepeatsActiveProfile`
