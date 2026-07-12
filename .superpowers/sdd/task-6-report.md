# Task 6 Report: Authenticated tvOS UX Proof And Performance Audit

Date: 2026-07-12

Branch: `codex/tvos-ux-polish`

Worktree: `/Users/flo/Documents/Projet/ReelFin/.worktrees/tvos-ux-polish`

Status: **DONE_WITH_CONCERNS**

## Outcome

The final authenticated tvOS pass proves Home and Library focus travel, compact Resume choice focus/cancel behavior, exact detail-source restoration, rapid Back handling, playback continuity, and safe behavior when circular input cannot be injected. The pass found and fixed a release-blocking Home return-focus defect caused by duplicate item IDs across shelves and by initial Detail state replacing the originating row target with Hero.

Home focus is now row-qualified, the originating source survives Detail presentation, and an automatic Hero fallback cannot cancel an active exact-card handoff. No production timeline behavior was changed.

## Authenticated Evidence

- Result: `.artifacts/player-e2e/task6/tvos-live-final-green.xcresult`
- Log: `.artifacts/player-e2e/task6/tvos-live-final-green.log`
- Result: 8/8 tests passed, zero failures, 384.118 seconds of test execution.
- Exact Home detail-return and rapid double-Back rerun: `.artifacts/player-e2e/task6/home-back-unique-focus-green.xcresult` (2/2 passed).
- Exported attachments: `.artifacts/player-e2e/task6/tvos-live-final-green-attachments`

Representative exported screenshots:

- Home landscape focus: `BF019344-DE21-4C5E-9BC3-78B738841514.png`
- Home poster focus: `849344B0-E8B9-44DC-B97E-BEAB4408E82D.png`
- Library left/middle/right: `3EC6EA16-7ADF-4246-99B1-D7DBF9AAFC72.png`, `EBE124CE-C6D8-4A2F-874E-8ADBB3692CBB.png`, `60786A9F-68F3-46DB-A104-55255C69B07F.png`
- Compact Resume choice: `1022E910-A449-42B3-96DD-79E6378E0DB5.png`
- Home transition opening/presented/closing: `E9E49E08-BD30-4977-A6DD-5E01B572D008.png`, `23ECD241-7477-4B81-BC9A-8C2E139ABB80.png`, `3FFEA9B9-BB86-4653-9A2C-A089FD4EB7B6.png`
- Library transition opening/presented/closing: `758D608B-1A1E-4A6D-ACBC-60D81B037B9A.png`, `A8D3D5A7-A6BC-4157-9335-39EFBBAAC518.png`, `1A8C9520-F40E-43D5-9100-F72FD7C77648.png`

Visual review accepted every frame: focused cards remain unique and fully visible, Library pans without clipping the right edge, the compact choice remains centered and within its width budget, and detail transitions preserve dim/scale/zoom continuity without a hard black cut.

## Circular Input And Fallback

The public Xcode 27 Device Hub controls expose cardinal directions, Select, Back, Home, Play/Pause, screenshot, and recording. They do not expose a clickpad or indirect-coordinate gesture, so exact circular input is reported as unavailable instead of being silently approximated.

The authenticated player journey verifies the exposed circular state remains idle with no preview and no player failure. Deterministic coverage separately passes 100 circular scrub sessions, -10/+30-second cardinal seeks, and live-stream seek-to-zero/forward behavior.

## Performance Probes And Code Audit

- Player UI probe: `.artifacts/player-ui-probe/20260712-200426`; two available checks passed and two credential-dependent live checks skipped.
- Playback QA loop: `.artifacts/playback-qa/20260712-200748`; 970 PlaybackEngine tests and six ImageCache tests passed, with ten expected live skips and zero failures.
- tvOS profile attempt: `.artifacts/player-e2e/task6/test_tvos_profile.log`; stopped before profiling because the script requires credentials intentionally not exported from the preserved signed-in container.
- No repeated per-frame glass construction, new display link, timer, detached work, broadened `MainActor` isolation, unbounded task, or uncanceled lifecycle work was introduced.
- Runtime logs showed no Main Thread Checker, Core Animation background-thread, unexpected stall, or player-error evidence.
- Focus restoration remains event-driven; fixed sleeps are limited to intentional activation dwell in test choreography, not production handoff.

## Final Verification

- Focused iOS suite: `.artifacts/player-e2e/task6/ios-targeted-final.xcresult`; 95/95 passed with zero failures/skips.
- Local tvOS suite: `.artifacts/player-e2e/task6/tvos-local-final.xcresult`; 2/2 passed with zero failures.
- Authenticated tvOS suite: `.artifacts/player-e2e/task6/tvos-live-final-green.xcresult`; 8/8 passed with zero failures.
- iOS build: `.artifacts/player-e2e/task6/ios-build-final.log`; succeeded.
- tvOS build: `.artifacts/player-e2e/task6/tvos-build-final.log`; succeeded.
- `xcodegen generate` succeeded.

## Review And Remaining Concerns

The final source/test diff was reviewed against the task contract and repository guardrails. The change is limited to exact Home focus identity/restoration, its regression contract, authenticated journeys, and audit documentation. No credential, server URL, authenticated item ID, or simulator state is tracked.

Simulator validation cannot prove physical clickpad feel, audible speaker/HDMI output, negotiated audio formats, HDR/Dolby Vision display-mode switching, tone mapping, or final panel luminance. Those remain explicit hardware validation items; they do not block the simulator-backed UX and correctness result.
