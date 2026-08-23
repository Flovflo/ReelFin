# Native Liquid Glass Player Redesign

## Objective

Rebuild ReelFin's custom playback chrome so it follows the supplied iOS and tvOS references while preserving the existing Apple-native playback routes. The visual layer must feel native to iOS 26 and tvOS 26, remain adaptive, and expose only controls backed by real playback behavior.

## Product principles

- A visible control always performs a real action. Unsupported actions are omitted instead of being simulated.
- The video renderer remains Apple-native: `AVPlayer`, `AVPlayerViewController`, `AVSampleBufferDisplayLayer`, `AVSampleBufferAudioRenderer`, and public AVKit/MediaPlayer APIs only.
- The two playback backends share one interaction contract, but iOS and tvOS retain platform-specific layout and input behavior.
- A user action receives immediate feedback. Audio and subtitle changes stay visibly pending until the playback state confirms the requested track.
- Content remains the visual priority. Chrome uses a restrained number of grouped Liquid Glass surfaces and a lower-edge legibility gradient.
- Background tap on iOS and Select/Menu behavior on tvOS remain deterministic and manually dismiss the chrome without waiting for auto-hide.

## Shared interaction contract

The chrome consumes a capability-and-action model rather than knowing which renderer is active. The model exposes:

- close;
- play/pause;
- seek backward 10 seconds;
- seek forward 10 seconds on iOS and the existing remote seek policy on tvOS;
- absolute timeline seek;
- audio selection;
- subtitle enable/disable and selection;
- subtitle background style;
- video/playback information;
- AirPlay through `AVRoutePickerView` where available;
- system volume through `MPVolumeView` on iOS;
- Picture in Picture only when a public `AVPictureInPictureController` bridge reports it possible;
- share only when the host supplies a safe share payload.

The model publishes capabilities so the presentation can remove unsupported buttons without leaving empty or misleading targets. In particular, the existing iOS Picture in Picture placeholder must disappear until it is connected to a real controller.

## Track-transition behavior

Audio and subtitle selection use an explicit state machine:

- `idle`: the confirmed engine selection is shown with a checkmark;
- `pending`: the requested row shows a progress indicator and the menu remains visible;
- `confirmed`: the engine-reported selection matches the request, the checkmark moves, and the menu dismisses where appropriate;
- `failed`: the old confirmed selection is restored and the row shows a short, understandable error.

The pending state is latest-wins and cancelable. A new choice replaces the previous request. The UI never claims success solely because a row was tapped.

## iOS presentation

The landscape chrome follows the supplied reference:

- top leading: separate circular close control, followed by one compact glass group containing only available PiP, AirPlay, and share actions;
- top trailing: native system volume slider in a glass capsule;
- center: circular 10-second rewind, prominent play/pause, and 10-second forward controls;
- bottom leading: concise media title and optional episode context;
- bottom trailing: one compact group for real video information, audio, and subtitle actions;
- bottom edge: a full-width glass timeline capsule with elapsed and remaining time;
- menus: anchored dark glass cards on the trailing side, using the subtitle On/Off → Language → Style hierarchy and a scrollable audio list;
- status: buffering and track-transition feedback are visible without blocking transport controls.

Sizing derives from the available landscape geometry and safe-area insets. Compact-width layouts reduce spacing and symbol size while preserving a minimum 44-point touch target. Liquid Glass uses `GlassEffectContainer`, interactive system glass, continuous circles/capsules, and the smallest practical number of rendering containers. Reduce Transparency receives an opaque high-contrast fallback.

## tvOS presentation

The tvOS chrome follows the supplied Apple TV captures:

- a subtle lower gradient over the video;
- top-center “Balayez vers le bas pour les infos” hint, backed by a real down-command route;
- lower leading episode context and large title;
- one nearly full-width timeline with elapsed time near the playhead and remaining time trailing;
- a compact lower-trailing row of circular controls ordered video, subtitles, audio, settings;
- anchored audio/subtitle cards above that row, with a white native focus surface and no second focus system;
- settings opens real playback information and item-detail destinations rather than decorative buttons.

The Siri Remote focus graph contains the timeline and every visible action exactly once. Menu closes submenu → panel → chrome → player. Play/Pause always reaches transport unless circular scrubbing intentionally consumes the press. No focus handoff uses fixed sleeps as its primary mechanism.

## Resume/restart choice

Movies and episodes with meaningful progress show the same compact centered decision on iOS and tvOS before playback starts:

- title/question at the top;
- vertical Resume button including the saved timestamp;
- vertical Start from Beginning button;
- Resume is the default tvOS focus;
- cancel returns to the previous screen without creating a playback session.

The panel uses a compact continuous glass rectangle, adapts its maximum width per platform, and does not start playback behind the dialog.

## Error handling and accessibility

- Every actionable control has a localized label, stable accessibility identifier, and truthful selected/pending value.
- Menus keep the currently selected or requested row visible.
- Track failures are logged without raw URLs, headers, tokens, or private track identifiers.
- Reduce Motion removes glass morphing and scale animation while preserving state changes.
- Reduce Transparency uses an opaque dark surface and white focus/selection contrast.

## Verification

- Add policy tests before implementation for capabilities, control order, focus routing, pending track transitions, adaptive geometry, and resume layout.
- Update UI tests to exercise real play/pause, seeks, chrome hide/reveal, audio/subtitle selection feedback, menu dismissal, and resume/restart.
- Run `xcodegen generate`.
- Build and test `ReelFin` on the current iPhone simulator runtime.
- Build and test `ReelFinTV` on the current Apple TV simulator runtime.
- Run `scripts/run_player_ui_probe.sh` and `scripts/run_playback_qa_loop.sh` when their configured fixture/server prerequisites are available.
- Capture simulator screenshots for side-by-side comparison with the supplied references.
- Record playback hot-path and validation results in `PLANS.md` and `OPTIMIZATION_AUDIT.md`.
