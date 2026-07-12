# tvOS UX Polish And Circular Remote Scrubbing Design

**Date:** 2026-07-12  
**Status:** Approved for implementation planning  
**Scope:** ReelFin tvOS Home, Library, Detail presentation, playback launch UI, and custom-player timeline interaction

## Objective

Polish ReelFin's tvOS experience so focus is unmistakable from couch distance, Home/Library/Detail navigation feels continuous, Back always returns inside the app before allowing system exit, playback launch UI is compact Liquid Glass, and the custom timeline supports a Siri Remote clickpad circular scrubbing gesture.

The work must preserve the already validated resume/restart exact-once behavior, seek-to-zero reliability, custom/native player routes, authenticated Jellyfin state, and iOS presentation.

## Non-Goals

- Do not replace ReelFin's custom player with `AVPlayerViewController`.
- Do not add third-party media, gesture, or animation frameworks.
- Do not use private tvOS APIs.
- Do not change Home data ordering, Library query semantics, Jellyfin progress reporting, or playback policy.
- Do not make iOS adopt tvOS focus geometry or tvOS modal sizing.
- Do not require a physical Apple TV for the implementation gate.

## Approach

Use one small tvOS interaction system rather than unrelated view-specific patches:

1. Extend the existing `TVMotion` roles with explicit Home landscape, Home poster, and Library poster metrics.
2. Introduce value policies for focus overflow, detail presentation phases, Back precedence, compact launch-card metrics, and circular scrub math.
3. Keep SwiftUI as the presentation layer and use a minimal UIKit `UIViewRepresentable` only to receive indirect clickpad pan samples that SwiftUI's cardinal `onMoveCommand` cannot express.
4. Drive visual state from deterministic values/tokens and animation completion rather than fixed sleeps as the primary focus/navigation mechanism.

## 1. Focus Visibility

### Home

Focused content must be obvious without turning the card into a white tile.

- Portrait/poster cards: scale `1.07`.
- Landscape/Continue Watching cards: scale `1.06`.
- Focused stroke: white opacity `0.28` to `0.34`, 1.4-point width.
- Focused shadow: opacity `0.48`, radius `34`, vertical offset `18`.
- Resting cards retain their current subtle opacity; focused text metadata rises to full opacity.
- Focus animation: spring response `0.28`, damping fraction `0.80`.
- Activation press remains a distinct short `1.02`–`1.03` phase on top of focus, never a second large zoom.

Home rails reserve enough vertical overflow for the larger scale and shadow. The focused card must not collide with a section title or be clipped by its horizontal scroll viewport.

### Library

- Library poster scale: `1.06`.
- Keep Liquid Glass only on the focused cell for performance.
- Add a scroll-content top reserve of at least `34` points plus the calculated scale overflow.
- Preserve the visible title and year below artwork while focused.
- The first row must remain fully visible at maximum focus scale and shadow radius.

### Reduced Motion

When Reduce Motion is enabled, retain the stroke/brightness change but cap scale at `1.02` and replace spring transitions with a short ease-out.

## 2. Home And Library To Detail Continuity

Home and Library must use the same detail-presentation phases:

```text
idle -> opening(source item) -> presented(item) -> closing(item) -> idle
```

- Opening duration: `0.34` seconds.
- Closing duration: `0.30` seconds.
- The selected artwork is the visual source using the existing namespace and transition-source IDs.
- The source artwork scales toward the detail artwork while the detail backdrop fades in.
- Detail identity, metadata, and controls fade/translate in after the artwork transition begins, so no opaque black sheet appears on frame one.
- Closing is the exact reverse: controls fade first, artwork returns toward its source, Home/Library regains full opacity and scale.
- Home/Library focus trees remain disabled while Detail is presented.
- Focus restoration uses the saved item ID and a request token after the source cell is mounted; no fixed delay is the primary handoff.
- If the original card is no longer present because data changed, restore the nearest valid item in the same row/grid.

Library must use the same explicit `onDismissRequest` contract as Home rather than relying only on an environment dismiss whose event can propagate to the app root.

With Reduce Motion, use a `0.18`-second crossfade and keep the same presentation/back state machine.

## 3. Back Precedence And Event Ownership

The Back/Menu button must have one owner at a time and execute exactly one transition:

```text
Resume popup -> cancel popup
Player panel/menu -> close panel/menu
Player -> close player and return to Detail
Detail -> close Detail and restore Home/Library focus
Root Home/Search/Library -> allow the system/app exit behavior
```

Requirements:

- An inline Detail keeps a stable closing host alive until its removal animation completes, so the same Back event cannot reach the root after Detail disappears.
- Repeated Back during `closing` is consumed and causes no additional dismiss.
- Detail opened from Home and Detail opened from Library share the policy.
- The directional Left command remains focus navigation; it must not pop Detail unless a specific focused control explicitly owns that behavior.
- A tvOS live marker exposes the active Back owner only under the existing exact DEBUG automation policy.

## 4. Compact Resume/Restart Card

The current modal is visually oversized. Replace its tvOS presentation with one compact Liquid Glass card:

- Maximum width: `760` points.
- Corner radius: `34` points.
- Horizontal/vertical padding: `44` / `34` points.
- Item title: 22-point semibold, secondary opacity `0.66`.
- Question: 32-point semibold, single or two-line maximum.
- Button row spacing: `16` points.
- Button height: `66` points; minimum width `270` points.
- Focused button scale: `1.025`.
- Focused white wash: opacity `0.20`; selected/resting glass never becomes an opaque white capsule.
- Resume time remains part of the Resume label.
- Default focus remains Resume.

The card owns one outer `.regular` Liquid Glass surface. Buttons use restrained interactive focus fills and must not create nested glass layers that hide text.

Exact-once behavior remains unchanged: Cancel launches nothing; Resume and Restart each emit one selection, one preparation, and one presentation.

## 5. Compact Player Preparation And Cache UI

Keep the current contextual backdrop, but replace the large-feeling launch treatment with a compact bottom-leading status card:

- Maximum content width: `420` points.
- Corner radius: `24` points.
- Padding: 20 horizontal / 16 vertical.
- Spinner: 34 points.
- Title: 21-point semibold.
- Status: 17-point medium at secondary opacity.
- Progress track: maximum width `280` points, 5-point height.
- tvOS screen inset: 64 points leading and bottom.
- Buffering/recovery pill uses the same visual language at a smaller intrinsic size.

The full-screen cached backdrop may remain until the first frame proves rendering, but the status UI cannot be a large centered modal. Slow-server Retry/Quit actions appear only after the existing slow threshold and remain real actions.

## 6. Circular Siri Remote Scrubbing

### Interaction

Circular scrubbing is available only when the player timeline owns focus.

1. An indirect clickpad pan begins scrubbing.
2. Record original time and whether playback was running; pause during preview.
3. Clockwise rotation moves forward; counter-clockwise moves backward.
4. The timeline, current time, remaining time, and scrub marker update continuously.
5. Center click commits the pending seek and resumes only if playback was running before the gesture.
6. Back cancels, seeks to the original time, and restores the original play/pause intent.
7. Left/Right presses retain the existing `-10` / `+30` second shortcuts outside circular scrub mode.

### Gesture Adapter

Add a tvOS-only `UIViewRepresentable` backed by a public `UIPanGestureRecognizer` configured for indirect touch input. It forwards normalized samples to a pure Swift policy:

```swift
struct TVRemoteScrubSample: Equatable, Sendable {
    let location: CGPoint
    let center: CGPoint
    let timestamp: TimeInterval
}

enum TVRemoteCircularScrubPolicy {
    static func angularDelta(previous: TVRemoteScrubSample, current: TVRemoteScrubSample) -> Double
    static func secondsPerRevolution(duration: Double) -> Double
    static func velocityMultiplier(radiansPerSecond: Double) -> Double
    static func target(original: Double, accumulatedRadians: Double, duration: Double) -> Double
}
```

- Angle deltas unwrap across `-π` / `π` so crossing the top of the clickpad does not jump.
- Ignore samples inside a small center dead zone.
- Base seconds per revolution is `clamp(duration / 30, 30, 300)`.
- Slow rotation multiplier: `0.5`; normal: `1`; fast: up to `4`.
- Every target is clamped to `[0, duration]`.
- Seeking remains latest-wins and cancelable; the gesture must not queue unbounded AVFoundation seeks.
- No media IDs, timestamps tied to item identity, URLs, or auth values are logged.

If indirect touch location is unavailable in a specific Simulator host configuration, cardinal shortcuts remain functional and the pure angle/state policy remains fully testable. This fallback must be explicit rather than silently pretending circular input succeeded.

## 7. Accessibility And Focus

- Focused cards and controls expose `focused` / `not_focused` values only behind existing DEBUG live markers where needed.
- Resume/Restart labels remain spoken as complete actions including the resume time.
- Scrub mode announces the preview time at a throttled cadence, not on every raw gesture sample.
- Back-owner markers contain only enum-like screen names.
- All tappable/focusable controls perform real actions.

## 8. Performance Guardrails

- No live Liquid Glass on every resting Library/Home card.
- Do not add a full-screen Gaussian blur to Home/Detail transitions.
- Gesture processing is O(1) per sample and never triggers artwork/network requests.
- Focus warmup stays latest-wins and cancelable.
- Transition artwork uses authenticated cached image loading and existing cache keys.
- No fixed sleeps as the primary focus or Back-navigation mechanism.

## 9. Validation

### Deterministic Tests

- Exact focus scales and overflow reserves for Home landscape/poster and Library.
- Library first-row top inset at maximum focus geometry.
- Detail presentation state transitions and repeated-Back consumption.
- Home and Library Back routes restore the correct prior item.
- Compact Resume card and loading-panel metrics.
- Resume/Restart/Cancel exact-once behavior.
- Circular angle unwrap, dead zone, direction, velocity multiplier, duration scaling, clamping, commit, and cancel.
- Existing seek-to-zero, audio/subtitle, player focus, and resolver tests remain green.

### Authenticated tvOS Simulator Journeys

Use Apple TV 4K (3rd generation), tvOS 27 simulator `092D088B-6307-4EFB-AE53-2457C2EE7F1A` without reset, uninstall, or sign-out.

- Home: move through landscape and poster rails; screenshot focused/resting pairs.
- Open Detail from Home; Back returns to the exact card and the app remains foreground.
- Open Detail from Library; Back returns to the exact poster and the app remains foreground.
- Focus every first-row Library position and prove no clipping.
- Capture compact Resume/Restart and launch/cache states.
- Verify Left/Right timeline shortcuts, circular scrub state/commit/cancel where Simulator indirect input is available, pause/resume, seek to zero, and no player error.
- Re-run the ten-cycle Continue/Restart journey after shared focus/back changes.

### Final Gates

- `xcodegen generate`
- focused layout/navigation/scrub/player suites
- iOS Simulator build and regression suite
- full `ReelFinTV` scheme on the authenticated tvOS simulator
- `git diff --check`
- update `PLANS.md` and `OPTIMIZATION_AUDIT.md` with counts, durations, captures, and Simulator gesture/audio/HDR limitations

## Acceptance Criteria

- Couch-distance focus is immediately visible on Home and Library.
- No focused first-row Library poster is clipped.
- Home/Library ↔ Detail transitions have no black-frame hard cut.
- Back from Detail returns inside ReelFin exactly once and never exits the app.
- Resume/Restart and preparation/cache UI are materially smaller and use restrained Liquid Glass focus.
- Circular clickpad motion scrubs predictably with commit/cancel semantics and no crash or seek backlog.
- Existing player reliability gates remain green.
