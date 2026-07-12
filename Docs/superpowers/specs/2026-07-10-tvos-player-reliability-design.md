# tvOS Player Reliability and Apple-Style Chrome Design

## Goal

Make ReelFin's tvOS player reliable under resume, restart, repeated seeking, track changes, and
presentation/dismissal. Present an Apple-style, content-first interface close to the supplied
reference and the ReelFin iOS player without sacrificing Direct Play, original Jellyfin bytes,
HDR/Dolby Vision metadata, or authenticated playback.

## Chosen approach

Use a hybrid architecture:

- keep AVKit for media routes it can play natively;
- keep ReelFin's Apple-framework sample-buffer route for original Matroska playback;
- harden the sample-buffer route as a serialized, generation-owned state machine;
- share launch intent and presentation policies across iOS and tvOS;
- implement a compact SwiftUI tvOS chrome that follows familiar AVKit interaction semantics.

A small patch to the current restart code would leave network sessions and renderer callbacks able
to outlive a seek. Replacing all custom playback with `AVPlayerViewController` would simplify the
interface but would give up ReelFin's native original-Matroska path. The hybrid design fixes the
identified lifecycle defects while preserving supported original-quality routes.

## Confirmed runtime failure pattern

The supplied runtime log is a Matroska sample-buffer handoff (`item=06ef8fad`), not the AVPlayer
MOV path. One reader starts normally, then at least ten `sampleReader.start` sequences appear with
repeated video/audio renderer starts. Network buffer allocation errors follow the restart burst.
The log contains no exception backtrace or `.ips` crash report, so it does not prove a process
crash; it does prove that multiple playback generations overlap until the player collapses or
dismisses.

The unrelated Direct Play preheat timeout and temporary zero-width AVKit constraints are not the
primary failure for this item.

## Playback launch intent

Every movie or episode with meaningful saved progress presents a focused choice before starting a
media pipeline on iOS and tvOS:

- `Continuer à <time>` starts from Jellyfin's saved position and receives initial focus;
- `Recommencer` starts at zero;
- Back/Menu cancels without changing Jellyfin progress;
- completed items at or above 97 percent do not present the choice.

The chosen `PlaybackStartPosition` is passed identically to AVKit and sample-buffer playback.
Movie, episode-card, Home, and Detail launches must not silently apply different resume rules.

## Serialized seek and resource ownership

Remote movement updates an immediate preview target. A 280 ms debounce commits only the latest
intent, but correctness must not depend on the user pressing faster than the debounce.

Each committed playback generation owns:

- exactly one demux/read task;
- exactly one cancellable `MediaByteSource`;
- its audio/video drain callbacks and timers;
- the renderer state it is allowed to mutate;
- diagnostic, playback-time, subtitle, and completion publications.

Before replacement, the controller invalidates the old generation, cancels its byte source, waits
for the read task, synchronously quiesces both render queues, balances every media-data request with
`stopRequestingMediaData()`, then flushes renderers. Only after teardown completes may the next
generation open a source or enqueue samples. Stale callbacks are rejected at publication and
renderer boundaries.

The final target always wins across direction changes such as `600 → 480 → 700`. Seeking to zero is
valid. A forward seek may remain in-place only while a live generation owns an active demuxer;
cancelled or retiring tasks are never considered seekable.

Stop, temporary disappearance, and track reload share the same teardown contract. A temporary
disappearance either relaunches from the current time on reappearance or preserves an explicitly
documented active session; it must never leave a stopped controller that refuses to reconfigure.

## tvOS chrome and navigation

Video remains edge-to-edge. Revealing controls presents one lower gradient containing:

- an episode eyebrow or year and a large title;
- a thin, focusable timeline with elapsed and remaining time;
- compact Liquid Glass actions for Audio, Subtitles, and Video/display information;
- a right-anchored track popover matching the supplied reference;
- contextual Skip Intro/Credits actions only while their segments are active.

There are no Home/Search/Library controls or diagnostics in the normal playback chrome. Liquid
Glass uses native SwiftUI APIs, groups adjacent controls in `GlassEffectContainer`, and applies
interactive glass only to focusable controls.

Remote semantics are deterministic:

- Select reveals chrome or activates the focused control;
- Play/Pause always toggles transport;
- Left/Right on the timeline scrubs and previews the target;
- Up/Down moves between timeline and metadata actions;
- Menu closes a popover first, then hides chrome, then exits playback;
- focus returns to the launch card after dismissal without a fixed sleep.

## User-visible error behavior

Buffering is visible but does not steal focus. Recoverable transport failures keep the player open
and offer Retry/Close. Fatal decoder or route failures show the actionable reason without exposing
signed URLs or credentials. A retry starts a fresh generation after full teardown; it never layers
a new reader over the failed one.

## Validation strategy

### Deterministic tests

- launch-choice policy for movies and episodes, including completed items and cancellation;
- seek-to-zero, rapid backward coalescing, and alternating backward/forward final-target wins;
- source cancellation before replacement and no more than one active reader;
- renderer queue quiescence before flush and no callback after dismantle;
- temporary disappearance/reappearance and track reload;
- focus, Menu hierarchy, chrome layout, and track-popover policy.

### Automated user journeys

Add a tvOS UI-test target using `XCUIRemote` so tests drive the same directional, Select,
Play/Pause, and Menu inputs as a viewer. On the tvOS 27 simulator, exercise:

- Detail → Continue and Detail → Restart;
- visible video, audible playback evidence, and advancing playback time;
- pause/resume, repeated +30/-10 seeks, deep resume around eight minutes, and seek to zero;
- Audio/Subtitles menus and continuity after changing tracks;
- chrome hide/reveal, Skip action when available, dismissal, and restored focus;
- repeated launch/seek/dismiss loops with screenshot and runtime-log capture.

### Real Jellyfin and Apple TV Flo

Update-install and launch ReelFinTV on the connected `Apple TV Flo` (tvOS 26.5) without uninstalling
the app, erasing its container, signing out, or resetting the device. Reuse its existing authenticated
Jellyfin state. Validate at least one MP4/MOV AVKit item and one Matroska sample-buffer item, plus the
configured HDR and Dolby Vision items when available.

The acceptance loop checks first frame, audio, advancing time, pause/resume, aggressive seeks,
8-minute-to-zero, track changes, sustained playback, and clean exit. Run repeated loops while
capturing process/device logs and memory/network evidence. Signed URLs, API keys, usernames, and
passwords never appear in reports.

Simulator evidence validates routing, UI, focus, and decoder behavior, but never claims physical
HDR/Dolby Vision display correctness. Physical Apple TV/display validation is recorded separately.

## Acceptance criteria

- One active reader/source/render generation at all times.
- No stale callback can enqueue, publish time, or mutate diagnostics after replacement/dismissal.
- Seek to zero and repeated/alternating seeks preserve a usable player with audio and video.
- Continue/Restart works for both movies and episodes on iOS and tvOS.
- The tvOS chrome matches the content-first hierarchy and navigation behavior above.
- iOS and tvOS builds pass on installed runtimes; targeted and full regression suites pass.
- Automated tvOS user journeys pass on the simulator.
- Real Jellyfin playback passes on Apple TV Flo without deleting authenticated state.
- `PLANS.md` and `OPTIMIZATION_AUDIT.md` record measured results and any hardware-only caveats.
