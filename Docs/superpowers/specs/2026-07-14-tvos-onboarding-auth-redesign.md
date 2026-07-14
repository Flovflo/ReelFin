# ReelFin tvOS Onboarding and Authentication Redesign

**Date:** 2026-07-14  
**Status:** Approved by the user through the instruction to proceed without further questions  
**Platforms:** tvOS 26 and later only for the redesigned surface; iOS behavior must remain unchanged

## Problem

The current tvOS onboarding reproduces a physical television inside the television screen, mounts all four 1080p scenes at once, adds several small marketing callouts, and then covers the lower part of that presentation with a large glass panel. The result is visually crowded, difficult to read from a sofa, and less polished than the iOS onboarding.

The interaction model also has release-blocking issues:

- initial focus depends on a fixed 120 ms sleep;
- the remote Menu button does not move backward through onboarding or authentication stages;
- the first onboarding page keeps an invisible disabled Back button in the focus layout;
- generic focus identifiers can survive a route change and point to an unrelated or missing control;
- progress, fields, and authentication controls lack stable accessibility semantics and UI-test identifiers;
- some animation and focus feedback ignores Reduce Motion.

## Goals

1. Preserve the successful four-step iOS narrative while making the presentation native to a 16:9 living-room display.
2. Make the current page understandable within two seconds from a sofa: one image, one title, one explanation, one primary action.
3. Use Liquid Glass only for interactive controls and compact control grouping, not as a giant content panel.
4. Give every route a deterministic default focus without sleeps.
5. Make Menu/back navigation predictable and cancel in-flight Quick Connect work when leaving that route.
6. Keep Quick Connect as the preferred authentication path while retaining password login.
7. Add deterministic unit and tvOS UI coverage that does not require a real Jellyfin server.
8. Preserve the existing authenticated simulator data; validation uses mock launch arguments or installs over the existing app without erasing its data container.

## Non-goals

- No change to the iOS onboarding or iOS authentication layout.
- No third-party media, navigation, or design dependencies.
- No server discovery protocol or new Jellyfin API behavior.
- No redesign of Home, Search, Library, Detail, or the player in this work item.
- No physical Apple TV deployment or testing.

## Considered Directions

### A. Cinematic full-bleed deck — selected

Use the existing 16:9 ReelFin screenshots as edge-to-edge scene artwork with a restrained scrim. Place large copy in the lower-left safe area and a compact action rail in the lower-right safe area. Remove the physical TV, pedestal, and all screenshot callouts.

This direction has the strongest 10-foot hierarchy, uses the fewest simultaneous effects, and most closely matches tvOS presentation conventions.

### B. Stable two-column stage

Keep copy on the left and an unframed screenshot on the right. This is easier to compare with the iOS layout but feels more like a setup form and less like an Apple TV experience.

### C. Setup-first welcome

Reduce onboarding to one welcome page followed by Quick Connect. This minimizes completion time but discards the four-part product story the user explicitly likes on iOS.

## Visual Design

### Scene

- The current screenshot fills the complete 16:9 canvas with aspect-fill cropping.
- A subtle scale from 1.00 to at most 1.025 may run while a page is visible. Reduce Motion disables it completely.
- A single gradient scrim runs from transparent in the upper-right to approximately 78% black in the lower-left and approximately 48% black along the bottom.
- Only the active page is rendered. Inactive 1080p scenes are not kept in the view hierarchy with blur and shadow effects.
- No television bezel, stand, floating badge, mini badge, or marketing callout is displayed.

### Safe area and hierarchy

- All essential content stays at least 80 pt from the left and right edges and 60 pt from the top and bottom edges at 1920×1080.
- The brand is quiet and remains at the top-left safe edge.
- The copy block is anchored to the lower-left and is no wider than 820 pt.
- The action rail is anchored to the lower-right and never overlaps the copy block.
- The current title uses 60 pt bold text, with a maximum of two lines.
- Supporting copy uses 30 pt medium text, with a maximum of three lines.
- Primary button labels use at least 29 pt semibold text.
- Progress is visually compact but exposes “Step N of 4” as one accessibility value.

### Liquid Glass

- On tvOS 26+, the primary action uses `.buttonStyle(.glassProminent)` and secondary/back actions use `.buttonStyle(.glass)`.
- Adjacent controls are grouped in one `GlassEffectContainer` when available.
- No noninteractive full-screen or large content panel receives interactive glass.
- Focused controls use the native prominent glass response plus ReelFin’s existing 1.06 focus scale/elevation token when a supplemental cue is necessary.
- Reduced Motion keeps the contrast change but removes scale and spring movement.

## Page Narrative

The deck keeps four stable pages and the existing version gate:

1. **Your Jellyfin on Apple TV** — native big-screen browsing and fast resume, using the Home screenshot.
2. **Find what to watch** — posters, rails, seasons, and remote-first navigation, using a focused crop of Home/Library.
3. **Know the playback path** — Direct Play clarity through Apple’s native playback path, using Detail.
4. **Connect in seconds** — Quick Connect from another device, with password login as an alternative, using the connection scene.

The final button reads **Connect My Server**. Earlier buttons read **Continue**.

## Interaction and Focus

### Onboarding

- `.defaultFocus` assigns the primary CTA as soon as the focus scope exists; there is no fixed sleep.
- Select on the primary CTA advances one page or completes the deck.
- A compact visible Back control exists only on pages 2–4; it is absent, not transparent, on page 1.
- Menu on pages 2–4 moves back exactly one page and restores focus to the primary CTA.
- Menu on page 1 is consumed without changing app state, preventing an accidental exit during setup.
- Each page change uses a short crossfade and small horizontal offset. Reduce Motion uses a crossfade only.

### Authentication

- Landing defaults to Quick Connect.
- Server entry defaults to the server address field.
- Credentials defaults to username, or password after a failed credential submission.
- Quick Connect defaults to **Use Password Instead** only when that is the sole action.
- Each screen uses route-specific focus identifiers; a focus identifier is never reused for an unrelated control on another route.
- Menu behavior:
  - server → landing;
  - credentials → server;
  - Quick Connect → the route that launched it, while cancelling polling;
  - submitting/success ignore Menu while the state transition is atomic;
  - landing consumes Menu without mutating state.
- Visible Back buttons and Menu invoke the same navigation reducer.

## State and Code Structure

### `TVOnboardingDeckState`

A small value type owns page clamping, `isFirstPage`, `isLastPage`, `advance()`, and `retreat()`. The view owns it in `@State`. Stable array offsets, not arbitrary content IDs, drive navigation.

### `TVAuthNavigationPolicy`

A pure policy maps each authentication phase to its preferred focus and handles back destinations. Quick Connect records its launch origin so Menu returns to the correct stage.

### Views

- `TVOnboardingView` remains the orchestration point.
- `TVOnboardingHeroView` renders only the current full-bleed scene and scrim.
- `TVOnboardingContentView` renders copy and accessible progress.
- `TVOnboardingActionRail` renders only real actions.
- `TVLoginView` keeps the existing view models and async behavior but delegates focus and back routing to the policy.
- `TVLoginVisualSystem` continues to own reusable authentication controls and adopts semantic tvOS metrics and Reduce Motion-aware focus treatment.

## Accessibility

- Decorative screenshots and gradients are hidden from accessibility.
- The active page combines title and explanation in reading order.
- Progress exposes label “Onboarding progress” and value “Step N of 4”.
- Every actionable control has a stable identifier and useful label.
- Hidden controls are removed from the hierarchy.
- Increased contrast preserves legible text and control boundaries.
- Reduce Motion disables continuous drift, blur transitions, spring bounce, and scale-based focus movement.

## Testing and Acceptance

### Unit tests

- initial, minimum, and maximum page clamping;
- advance, retreat, first/last-page behavior;
- preferred focus for every authentication route;
- back destination for every route, including Quick Connect origin;
- layout constants at 1920×1080 and 1280×720 remain inside the required safe area;
- Reduce Motion policy disables drift, scale, blur, and bounce.

### Mock tvOS UI tests

- launch each onboarding page through existing debug arguments;
- verify the primary CTA is focused without remote movement;
- advance, use Menu to retreat, and confirm the app remains active;
- confirm Back does not exist on page 1;
- complete the deck and verify Quick Connect is the default login action;
- navigate server and credential stages and verify Menu follows the reducer;
- verify focused controls remain within the 80×60 safe rectangle.

### Manual simulator validation

- Use only the already-running Apple TV 4K (3rd generation) simulator.
- Capture all onboarding and authentication stages at 1920×1080.
- Compare focus, legibility, and overlap against the baseline captures.
- Relaunch normally after mock validation; do not erase, uninstall, or reset the simulator.

### Build gates

- `xcodegen generate`
- tvOS unit tests and tvOS auth UI tests on the current simulator
- complete `ReelFinTV` build
- complete iOS `ReelFin` build to prove platform isolation

## Rollout and Documentation

- The onboarding version remains unchanged unless the product intentionally wants already-onboarded users to see the new tour again.
- Record focus, launch, and auth changes in `PLANS.md` and `OPTIMIZATION_AUDIT.md`.
- Broader audit findings—root launch spinner, Settings reachability, global focus visibility, typography, explicit error states—remain separate follow-up work so this redesign stays testable and does not destabilize unrelated authenticated screens.
