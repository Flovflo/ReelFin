# Playback Architecture (Current - 2026-04-05)

This document describes the real playback stack that ships in ReelFin today.
It is intentionally implementation-oriented: if this file disagrees with the code,
the code wins and this file should be updated.

Scope:

- iPhone and iPad playback path
- tvOS-specific behavior where it diverges
- session ownership, route selection, startup, recovery, tracks, subtitles, HDR, and diagnostics

Primary source files:

- `PlaybackEngine/Sources/PlaybackEngine/PlaybackSessionController.swift`
- `PlaybackEngine/Sources/PlaybackEngine/PlaybackCoordinator.swift`
- `PlaybackEngine/Sources/PlaybackEngine/PlaybackDecisionEngine.swift`
- `PlaybackEngine/Sources/PlaybackEngine/PlaybackSessionController+SkipSegments.swift`
- `ReelFinUI/Sources/ReelFinUI/Player/PlayerView.swift`
- `ReelFinUI/Sources/ReelFinUI/Player/NativePlayerViewController.swift`
- `ReelFinUI/Sources/ReelFinUI/Player/TrackPickerView.swift`
- `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`
- `ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift`

---

## 1. High-level model

ReelFin does not own a custom video renderer.
It builds a playback plan, prepares an Apple-native `AVPlayer` / `AVPlayerItem`,
and presents that through `AVPlayerViewController`.

The stack is layered like this:

| Layer | Main type | Responsibility |
|---|---|---|
| Presentation owner | `HomeView` / `DetailView` | Creates and dismisses the playback session |
| Player screen | `PlayerView` | Hosts the native player wrapper and orientation behavior |
| Native bridge to UIKit | `NativePlayerViewController` | Wraps `AVPlayerViewController` for SwiftUI |
| Session orchestrator | `PlaybackSessionController` | Owns `AVPlayer`, observers, startup, recovery, progress, tracks |
| Playback resolution | `PlaybackCoordinator` | Fetches playback sources and turns them into a resolved asset URL |
| Route decision | `PlaybackDecisionEngine` | Chooses direct play vs remux vs transcode vs dormant NativeBridge |
| Capability planning | `CapabilityEngine` | Produces a `PlaybackPlan` lane from source/device constraints |
| Diagnostics | `PlaybackProofSnapshot`, `PlaybackPerformanceMetrics` | Captures runtime proof, bitrate, TTFF, failures |

The core idea is:

1. Resolve the best route for the current source and device.
2. Normalize the URL for compatibility and startup speed.
3. Feed Apple playback APIs only supported inputs.
4. Detect bad startup states quickly.
5. Retry with a safer transcode profile before surfacing failure.

---

## 2. Ownership and lifecycle

### 2.1 Who creates the session

The playback session is created outside the player view, from the main app UI.
The important ownership rule is:

- parent views own session lifetime
- `PlayerView` only hosts the session visually

Current dismissal flow:

- `HomeView` presents `PlayerView` inside `fullScreenCover`
- `DetailView` does the same
- when the cover is dismissed, `handlePlayerDismissal()` calls `playerSession?.stop()`
- the session is then nulled out by the parent view

This is deliberate.
`PlayerView` no longer calls `session.stop()` in `onDisappear`.
That change prevents accidental teardown during transient SwiftUI or AVKit view transitions.

### 2.2 What `PlayerView` does

`PlayerView` is intentionally thin:

- black background
- embeds `NativePlayerViewController`
- forwards audio/subtitle/skip callbacks into `PlaybackSessionController`
- manages iOS orientation lock while visible

It does not decide what to play.
It does not own playback teardown.

### 2.3 What `PlaybackSessionController.stop()` does

`stop()` is a hard session teardown.
It:

- pauses the player
- tears down current item observers
- removes the current item from the `AVPlayer`
- resets public playback state
- clears diagnostics and transport state
- cancels watchdogs and polling tasks
- stops any local synthetic HLS server
- persists the latest progress snapshot
- reports playback stopped to Jellyfin
- invalidates any active NativeBridge session

`stop()` is the right place to end playback.
View disappearance is not.

---

## 3. UI embedding and native player behavior

### 3.1 `NativePlayerViewController`

ReelFin uses `UIViewControllerRepresentable` to host `AVPlayerViewController`.

iOS configuration:

- `showsPlaybackControls = true`
- `entersFullScreenWhenPlaybackBegins = false`
- `exitsFullScreenWhenPlaybackEnds = false`
- `allowsPictureInPicturePlayback = true`
- `canStartPictureInPictureAutomaticallyFromInline = false`

tvOS configuration:

- native transport controls remain visible
- custom audio/subtitle menus are injected through `transportBarCustomMenuItems`

### 3.2 Media-selection behavior

There are two relevant places where media-selection behavior is configured:

- base player setup in `PlaybackSessionController.configurePlayerBase()`
- controller-specific setup in `NativePlayerViewController`

Current runtime behavior:

- base player starts with `appliesMediaSelectionCriteriaAutomatically = false`
- on iOS, when wrapped in `AVPlayerViewController`, the player is set to `true`
- on tvOS, it stays `false` because ReelFin provides its own menus

Practical meaning:

- iOS can expose native AVKit audio/subtitle menus when the asset has real media-selection groups
- tvOS avoids duplicate menus and relies on `PlaybackControlsModel`

### 3.3 iOS reattach workaround

The iOS player has a targeted workaround for a known AVKit race:

- SwiftUI presents `AVPlayerViewController`
- the `AVPlayer` may exist before the `AVPlayerItem` becomes ready
- if the item arrives late, AVKit can show audio with no video surface attached

To fix this, `NativePlayerViewController.Coordinator` observes:

- `player.currentItem`
- current item `status`

When the active item reaches `.readyToPlay`, it temporarily detaches and re-attaches
the player to `AVPlayerViewController`.

Important details in the current implementation:

- only one reattach is allowed per item
- pending reattach work is canceled when the item changes
- the coordinator tracks the observed item with `ObjectIdentifier`
- stale callbacks are rejected using a monotonically increasing generation counter
- the delayed reattach only resumes playback if there was actual playback intent

This is one of the most important stability patches in the current UI layer.

### 3.4 Skip UI

On iOS, skip-intro / next-up suggestions are displayed through
`PlaybackSkipOverlayView`, installed into `contentOverlayView`.

On tvOS, the same suggestion is exposed via transport bar menu actions.

---

## 4. Session state model

`PlaybackSessionController` is the runtime source of truth for a single active session.

Important published state:

- `isPlaying`
- `currentTime`
- `duration`
- `availableAudioTracks`
- `availableSubtitleTracks`
- `selectedAudioTrackID`
- `selectedSubtitleTrackID`
- `activeSkipSuggestion`
- `runtimeHDRMode`
- `metrics`
- `playbackErrorMessage`
- `playbackProof`
- `transportState`

### 4.1 `transportState`

`transportState` is a compact snapshot used by the UI layer.
It contains:

- available audio tracks
- available subtitle tracks
- selected audio track ID
- selected subtitle track ID
- active skip suggestion

Updates are batched by `PlaybackTransportStateCommitter` with a short delay.
That avoids spamming SwiftUI with multiple fast state changes during startup and track reloads.

### 4.2 `playbackProof`

`playbackProof` is not UI decoration.
It is a structured proof of what actually happened at runtime:

- decoded resolution
- codec fourCC
- bit depth
- detected HDR transfer
- Dolby Vision active or not
- selected variant metadata
- source metadata
- player item status
- fallback reason
- failure domain / code / recovery suggestion

If you need to answer "what did we really end up playing?", this is the state to inspect.

---

## 5. End-to-end startup flow

The startup path begins in `PlaybackSessionController.load(item:autoPlay:upNextEpisodes:)`.

### 5.1 Session reset

At the top of `load()`, the session clears previous playback state:

- resets timing and metrics
- clears playback proof
- clears error state
- cancels startup tasks
- resets variant and init-segment inspections
- resets fallback tracking
- clears old transport state
- starts marker refresh for intro/outro segments

### 5.2 Server configuration snapshot

The session reads the current server playback configuration and snapshots:

- `playbackPolicy`
- `allowSDRFallback`
- `preferAudioTranscodeOnly`
- `preferredAudioLanguage`
- `preferredSubtitleLanguage`

From this it derives:

- `playbackQualityMode`
- initial `activeTranscodeProfile`
- whether strict HDR/DV protection is active

### 5.3 Resume handling

Before fetching playback sources, the session resolves resume position.
This is critical.

If a resume point exists:

- it is converted to `StartTimeTicks`
- `PlaybackCoordinator.resolvePlayback()` is called with that start offset
- Jellyfin can start the transcode close to the real resume point

Why this matters:

- direct seek after startup is fragile on server HLS
- starting the server stream at the correct time dramatically reduces restart and wait states

### 5.4 Warmup

If there is no resume point, the session may reuse a warmed `PlaybackAssetSelection`
from `PlaybackWarmupManager`.

That optimization exists to reduce TTFF on already-browsed content.

### 5.5 Asset resolution

After fetching or reusing a selection, startup continues through these phases:

1. `pinPreferredVariantIfNeeded`
2. `stabilizeInitialSelectionIfNeeded`
3. `upgradeRiskyInitialSelectionIfNeeded`
4. attempt de-duplication with `registerAttempt`

These phases try to avoid obviously bad first attempts before the player is even created.

### 5.6 Route-specific preparation

If the chosen route is `.nativeBridge(plan)`:

- the code can prepare either a local synthetic HLS server or a resource-loader-backed asset
- however, shipping route selection keeps NativeBridge disabled, so this path is dormant in production

If the route is not NativeBridge:

- any previous bridge session is invalidated
- local HLS infrastructure is torn down

### 5.7 Preparing the player item

`prepareAndLoadSelection()`:

- validates the asset URL
- builds an `AVURLAsset`
- explicitly avoids unsupported header injection APIs
- creates an `AVPlayerItem`
- installs `AVPlayerItemVideoOutput`
- configures buffer duration
- replaces the current player item
- wires item observers
- starts video-output polling

Key policy:

- playback auth should be carried by URL query params, especially `api_key`
- ReelFin does not rely on unsupported `AVURLAssetHTTPHeaderFieldsKey`

### 5.8 First play

If `autoPlay` is true:

- `player.play()`
- decoded-frame watchdog starts
- startup watchdog starts

The session is then in startup-validation mode until the first real decoded frame arrives.

---

## 6. Route selection

### 6.1 Route types

`PlaybackDecisionEngine` can return:

| Route | Meaning |
|---|---|
| `directPlay(URL)` | Play the file more or less as-is using Apple-native support |
| `remux(URL)` | Use Jellyfin direct stream / HLS-compatible repackaging without full transcode when possible |
| `transcode(URL)` | Ask Jellyfin for a fully compatible transcode route |
| `nativeBridge(plan)` | Local MKV to fMP4 path; currently disabled for shipping route selection |

### 6.2 Decision order

The engine currently tries, in order:

1. raw direct play
2. plan-derived decision from `CapabilityEngine`
3. generic direct-play candidate
4. NativeBridge candidate, but only if the feature is enabled
5. remux candidate
6. transcode candidate
7. fallback transcode URL construction

### 6.3 What is important and easy to misunderstand

Important clarifications:

- MKV is not raw direct play in ReelFin
- MKV is not always a full transcode either
- compatible MKV sources may use `remux`
- incompatible MKV sources use `transcode`
- shipping builds keep `NativeBridge` disabled at route-selection time

So the correct mental model is:

- MP4/MOV/M4V can direct play if codecs are Apple-safe
- MKV can remux or transcode
- local MKV repackaging code exists but is dormant

---

## 7. Coordinator URL normalization and profiles

`PlaybackCoordinator` turns the route decision into a concrete `PlaybackAssetSelection`.

### 7.1 What it adds

It determines:

- the final asset URL
- the selected startup audio track
- effective transcode profile
- API key query injection
- debug info for logs and UI

### 7.2 Audio startup selection

Before the session even loads the asset, the coordinator chooses the preferred audio track
using `AudioCompatibilitySelector`.

That chosen track is injected into the URL as `AudioStreamIndex`.

This means startup audio selection is usually solved before AVPlayer starts reading media.

### 7.3 Effective transcode profile

Requested profile and effective profile are not always the same.

The coordinator may promote the request into a safer profile based on the source:

- iOS MKV + HEVC-family source tends to become `appleOptimizedHEVC`
- tvOS MKV transcode becomes `forceH264Transcode`

This distinction is important:

- requested profile describes what the session asked for
- effective profile describes what the runtime actually decided to load

### 7.4 Current profiles

| Profile | Runtime intent |
|---|---|
| `serverDefault` | Stay close to Jellyfin defaults, keep stream copy when safe |
| `appleOptimizedHEVC` | Force clean HEVC/fMP4 for Apple-friendly startup |
| `conservativeCompatibility` | Keep source codec when possible, normalize transport and audio |
| `forceH264Transcode` | Hard fallback for black-screen / no-frame / incompatible startup cases |

### 7.5 tvOS rule

On tvOS, MKV transcode is aggressively forced toward H.264 TS compatibility.
The code comments are explicit: H.264 TS is the only reliably decodable Jellyfin transcode path there.

---

## 8. Startup state machine

The observable startup path is:

```text
idle
  -> load() resets session
  -> playback sources fetched
  -> route chosen
  -> URL normalized
  -> AVURLAsset created
  -> AVPlayerItem created
  -> currentItem replaced
  -> item.status = readyToPlay
  -> startup validation
  -> first decoded frame
  -> steady playback
```

### 8.1 `readyToPlay` is not success

This is a critical runtime rule.

`AVPlayerItem.status == .readyToPlay` only means:

- AVFoundation accepted the item enough to begin playback attempts

It does not prove:

- decoded video exists
- presentation size is valid
- video renderer is attached
- first frame will actually appear

This is why ReelFin has:

- video-output polling
- decoded-frame watchdog
- startup watchdog
- post-ready validation

### 8.2 First-frame definition

ReelFin only marks startup complete when all of these are true:

- `currentSeconds > 0`
- `hasDecodedVideoFrame == true`
- `presentationSize.width > 1`
- `presentationSize.height > 1`

When that happens:

- startup watchdogs are canceled
- TTFF is recorded
- deferred resume seek can be applied
- the current profile can be remembered as working

---

## 9. Watchdogs and startup validation

There are three separate startup safety nets.

### 9.1 Post-ready validation

After `readyToPlay`, ReelFin waits a short validation delay and then checks:

- has a frame actually decoded?
- is presentation size valid?
- did playback advance without video?
- does the source look like risky HEVC stream-copy?

This catches "audio plays but video never appears" much earlier than waiting for a generic failure.

### 9.2 Startup watchdog

If no first frame appears within a profile-dependent deadline:

- recovery is attempted

If the item is already `readyToPlay`, ReelFin grants a bounded extension first.
That avoids premature fallback on slow but valid startups.

Current startup watchdog targets:

| Profile | Base timeout |
|---|---|
| `serverDefault` | 6 to 8 seconds |
| `appleOptimizedHEVC` | 10 to 14 seconds |
| `conservativeCompatibility` | 8 to 12 seconds |
| `forceH264Transcode` | 30 seconds |

### 9.3 Decoded-frame watchdog

If playback has advanced but no decoded frame appears quickly enough:

- recovery is attempted with a safer profile

This is specifically aimed at zombie startup states.

---

## 10. Recovery and failure model

### 10.1 Recovery entry points

Recovery can be triggered by:

- startup watchdog expiry
- decoded-frame watchdog expiry
- post-ready validation failure
- `AVPlayerItem.status == .failed`
- local synthetic HLS transport failure in dormant bridge flows

### 10.2 Recovery limits

Recovery count depends on playback policy:

- `auto`: up to 2 recovery attempts after the initial attempt
- stricter modes: fewer retries

If strict HDR/DV quality is active, recovery is more conservative and may refuse SDR downgrade.

### 10.3 Fallback semantics

When recovery is triggered:

- the attempt count increases
- `fallbackOccurred` and `fallbackReason` are recorded
- the session reloads with a safer transcode profile

The exact cascade differs by platform and source shape, but conceptually trends toward:

- keep original / copy when safe
- then clean HEVC
- then conservative compatibility
- then H.264 hard fallback

### 10.4 Terminal failure

If recovery cannot produce a valid route:

- `playbackErrorMessage` is set
- UI presents the alert from the parent screen

---

## 11. Audio behavior

### 11.1 Startup selection

Startup audio is selected by `AudioCompatibilitySelector`.
It uses a deterministic, language-aware scoring model.

Inputs include:

- preferred audio language from server configuration
- source default flags
- codec compatibility
- stream order

Broad behavior:

- preferred language strongly wins
- default track is heavily favored
- Apple-native codecs are preferred
- TrueHD and DTS are strongly penalized on the native path

### 11.2 Runtime audio switching

`selectAudioTrack(id:)` uses a two-stage strategy:

1. if the current asset exposes a native audible media-selection group, switch natively
2. otherwise rebuild the URL with `AudioStreamIndex` and replace the player item

The reload path preserves:

- current playback position
- current subtitle selection
- playback intent

This preservation is important because audio reload is an item replacement, not an in-place mutation.

---

## 12. Subtitle behavior

Subtitle behavior is one of the most important places to understand current UX.

### 12.1 Startup auto-selection

ReelFin still computes an automatic startup subtitle choice.
However, startup application is intentionally limited.

Current rule:

- embedded subtitles may be auto-applied at startup
- external subtitles are explicitly skipped at startup

Why:

- applying an external subtitle requires an HLS sidecar reload
- that reload replaces the `AVPlayerItem`
- doing that during startup made playback look like it restarted or stopped

This is a deliberate UX protection.

### 12.2 What "external subtitle skipped" means

If the chosen startup subtitle is external:

- `selectedSubtitleTrackID` may still reflect the logical choice
- but the player item is not reloaded automatically during startup
- the session logs that the external startup reload was skipped

In other words:

- ReelFin chooses not to disrupt startup to honor an external subtitle auto-choice

### 12.3 Runtime subtitle switching

`selectSubtitleTrack(id:)` also uses a two-stage strategy:

1. if the subtitle is exposed natively in the current legible media-selection group, switch in place
2. otherwise rebuild HLS with `SubtitleStreamIndex` and `SubtitleMethod=Hls`

For the fallback path:

- the base URL is `directStreamURL` if possible, otherwise `transcodeURL`
- current audio selection is preserved
- `api_key` is injected if missing
- the current playback time is restored after reload
- playback resumes only when the previous session had playback intent

### 12.4 Strict HDR guard

When strict HDR/DV quality is active, bitmap subtitles are blocked:

- PGS
- VobSub

Reason:

- selecting them can force a destructive transcode
- destructive transcode can drop HDR metadata

Text subtitles remain allowed.

---

## 13. Resume, seek, and progress

### 13.1 Absolute time vs HLS-relative time

For server HLS routes, ReelFin tracks:

- movie-absolute time
- HLS-stream-relative time

`transcodeStartOffset` bridges the two.

This is why:

- UI can show real movie time
- seeks can be expressed in movie time
- transcode sessions resumed from the middle remain coherent

### 13.2 Direct play vs transcode resume

Direct play:

- load the progressive or raw direct URL
- seek after item creation if needed

Transcode/remux:

- pass `StartTimeTicks` before startup
- let Jellyfin begin the stream near the resume point

### 13.3 Progress persistence

During playback, the periodic time observer:

- updates `currentTime`
- updates `duration`
- refreshes skip suggestions
- persists progress snapshots

On completion:

- `finishCurrentPlayback()` reports paused/finished state
- Jellyfin is told the item was played

On stop:

- a stopped snapshot is sent

---

## 14. Skip segments and next episode

Skip metadata comes from Jellyfin media segments.
`PlaybackSessionController+SkipSegments.swift`:

- fetches segments asynchronously
- keeps them sorted and filtered
- resolves the active suggestion for the current time

Two actions are currently supported:

- seek to a target timestamp
- jump to next episode

`nextEpisode` flow:

- finish current playback
- load next episode
- carry forward the remaining queue

---

## 15. HDR / dynamic range policy

### 15.1 Runtime modes

The runtime tracks:

- source-level HDR/DV likelihood
- expected output mode
- observed output mode after item readiness

Current broad expectations:

- direct play preserves the source best when Apple-native support exists
- HEVC transcode can preserve HDR10 better than H.264 fallback
- H.264 fallback is the compatibility escape hatch and usually means SDR

### 15.2 Strict quality mode

Strict quality is enabled when:

- the playback policy explicitly locks original HDR/DV quality
- or HDR/DV content is loaded with SDR fallback disabled

Strict mode blocks or rejects:

- SDR variants for HDR/DV content
- H.264 fallback routes
- TS transport where HDR carriage is unacceptable
- bitmap subtitle choices that would force destructive transcode

The user-facing consequence is intentional:

- playback may fail rather than silently downgrade HDR/DV

### 15.3 Logging

The session emits an explicit dynamic-range expectation log before playback starts.
This is the best place to answer:

- are we expecting DV?
- are we expecting HDR10?
- are we knowingly downgrading to SDR?

---

## 16. Diagnostics and observability

Important structured outputs include:

| Signal | Meaning |
|---|---|
| `Playback selected method=...` | Final startup method, container, codecs, profile |
| `Playback URL ...` | Final URL used, hashed in logs |
| `Audio selected: ...` | Why the startup audio track won |
| `Subtitle auto-selected: ...` | Which logical subtitle choice was made |
| `Skipping automatic external subtitle reload at startup` | Startup was protected from a disruptive item reload |
| `HDR expectation: ...` | Expected output dynamic range |
| `[NB-DIAG] avplayeritem.status` | Item state transitions |
| `[NB-DIAG] avplayer.first-frame` | First rendered frame timing |
| `TTFF ...` | End-to-end startup timing summary |
| `playback.fallback.triggered` | Recovery path activation |
| `Playback proof ...` | Runtime proof snapshot details |

### 16.1 TTFF

Time to first frame is measured as a real runtime metric.
The pipeline breaks out:

- playback info acquisition
- URL resolution
- ready-to-play time
- first frame time

### 16.2 Playback proof snapshot

If a user says "it played in the wrong format" or "it downgraded HDR",
`playbackProof` and its associated logs are the first place to inspect.

---

## 17. Dormant NativeBridge / local synthetic HLS

There is more code in the repo than what shipping route selection uses.

Current status:

- `PlaybackDecisionEngine.isNativeBridgeEnabled` returns `false`
- shipping route selection does not currently choose `.nativeBridge`

However, the runtime still contains:

- `NativeBridgeSession`
- `SyntheticHLSSession`
- `LocalHLSServer`
- local HLS preflight checks
- init/segment inspection and debug bundle export

Meaning:

- the bridge stack is under active engineering development
- the code is not dead
- but it is not part of the shipping selection path today

Do not document NativeBridge as an active production route unless that feature flag changes.

---

## 18. Platform differences

### iOS / iPadOS

- full-screen player is presented from SwiftUI
- native AVKit controls are used
- PiP is allowed
- reattach workaround exists for late-arriving items
- startup no longer tears down the session on `PlayerView.onDisappear`

### tvOS

- custom transport bar menus handle audio/subtitle selection
- tvOS-optimized Jellyfin device profile is always requested
- MKV transcode heavily favors H.264 TS compatibility
- buffering policy is more aggressive for living-room playback

---

## 19. Current limitations and sharp edges

These are the main current truths to keep in mind:

1. Raw MKV direct play is not the normal path. MKV is remuxed or transcoded.
2. External subtitles are intentionally not auto-applied during startup.
3. Track reloads still replace the current item; ReelFin only makes that replacement safer.
4. `readyToPlay` is not treated as success; decoded video is the real success condition.
5. NativeBridge exists in the codebase but is disabled in shipping route selection.
6. Strict HDR/DV mode prioritizes quality guarantees over "always play something".
7. The app lifecycle observer currently pauses on resign active and resumes on become active if playback was running.

---

## 20. Files to read first when debugging the player

If you need to debug a regression quickly, read in this order:

1. `PlaybackEngine/Sources/PlaybackEngine/PlaybackSessionController.swift`
2. `PlaybackEngine/Sources/PlaybackEngine/PlaybackCoordinator.swift`
3. `PlaybackEngine/Sources/PlaybackEngine/PlaybackDecisionEngine.swift`
4. `ReelFinUI/Sources/ReelFinUI/Player/NativePlayerViewController.swift`
5. `ReelFinUI/Sources/ReelFinUI/Player/PlayerView.swift`
6. `ReelFinUI/Sources/ReelFinUI/Player/TrackPickerView.swift`
7. `PlaybackEngine/Sources/PlaybackEngine/PlaybackSessionController+SkipSegments.swift`

Questions those files answer:

- Why was this route chosen?
- Why did playback downgrade?
- Why did startup recover or fail?
- Why did a subtitle switch trigger reload?
- Why did the native player show audio but no video?
- Who really stopped the session?

---

## 21. Focused validation commands

Useful local commands when changing the player:

```sh
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1'

xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:PlaybackEngineTests/PlaybackSessionControllerTrackReloadTests

xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.3.1' \
  -only-testing:PlaybackEngineTests/PlaybackPolicyTests \
  -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests \
  -only-testing:PlaybackEngineTests/CapabilityEngineTests
```

When editing:

- route selection logic: update decision and policy tests
- startup / reload / resume logic: update `PlaybackSessionControllerTrackReloadTests`
- NativeBridge internals: keep those tests separate unless route selection is actually enabled
