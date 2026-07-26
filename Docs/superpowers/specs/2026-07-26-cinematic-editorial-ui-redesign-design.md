# ReelFin Cinematic Editorial UI Redesign

- **Date:** 2026-07-26
- **Status:** Approved for implementation
- **Platforms:** iOS 26+ and tvOS 26+
- **Scope:** Home, Library/Search, Detail, shared browse motion, Liquid Glass control surfaces, and artwork delivery

## Objective

Make ReelFin feel more composed, editorial, and distinctly Apple-native without replacing the product's current cinematic identity or destabilizing its launch, focus, playback, and cache hot paths.

The selected direction is **Cinematic Editorial with Glass+**: deep black presentation, restrained champagne accents, artwork-first composition, logo-first identity, and clean Apple Liquid Glass on navigation and interactive control groups. Motion must be short, intentional, accessible, and cheaper than the visual work it replaces.

## User-Approved Direction

The user selected the following visual decisions through the browser companion:

- Direction A, Cinematic Editorial, over monochrome gallery and artwork-derived ambient alternatives.
- A restrained champagne accent rather than a global warm recoloring.
- A stronger Apple Liquid Glass treatment on navigation, grouped actions, compact floating controls, and the currently focused tvOS cell.
- No glass layer on resting artwork cards, full-screen backgrounds, or entire content sections.
- Simulator validation and fluidity are release requirements, not optional polish.

## Goals

1. Create one coherent browse visual system for iOS and tvOS while retaining platform-native navigation and focus behavior.
2. Improve information hierarchy on Home, Library/Search, and Detail so artwork, title, context, and the primary action read in that order.
3. Use native Liquid Glass more visibly and consistently without multiplying backdrop sampling across rails and grids.
4. Make carousel, press, focus, detail-entry, and loading motion short, interruptible, and Reduce Motion-aware.
5. Make artwork loading more reliable under fast scrolling and fast tvOS focus traversal by canonicalizing request variants, bounding speculative work, and preventing stale publication.
6. Reduce existing render costs before adding polish to the same surfaces.
7. Preserve cache-first Home rendering, authenticated artwork loading, exact focus restoration, native player routes, and existing transition identities.
8. Validate on the configured iPhone and Apple TV simulators with deterministic tests, UI journeys, screenshots, and comparative performance evidence.

## Non-Goals

- No redesign of onboarding, authentication, Settings, or the player chrome.
- No new discovery service, rating system, sharing product, alert feed, or watchlist backend.
- No change to Jellyfin ordering, Home feed semantics, Library result semantics, playback selection, or progress reporting.
- No third-party media engine, image framework, animation framework, or private Apple API.
- No artwork-derived full-screen palette extraction in this iteration.
- No Liquid Glass on every visible card or continuously animated blur radius.
- No replacement of the native iOS tab bar, iPad split view, tvOS top navigation focus topology, inline tvOS Detail presentation, or native zoom transition.
- No disk-cache format migration, global cache invalidation scheme, or artwork-version protocol in this iteration.

## Design Principles

### Content remains the hero

Artwork should dominate each screen. Chrome becomes quieter and more coherent, but controls remain unmistakable. Champagne is used for editorial kickers, active page indicators, progress, and subtle focused rims; primary text and primary actions remain high-contrast neutral white.

### Glass is interface, not decoration

Use Liquid Glass only where a physical control layer makes sense:

- iOS native tab/search presentation;
- tvOS top navigation selection;
- grouped Play, Favorite, and More actions;
- compact filter, sort, and section-forward controls;
- the currently focused tvOS media cell when extra focus separation is needed.

Do not apply interactive glass to backdrops, entire cards at rest, poster walls, section containers, or skeletons.

### Motion communicates state

Every animation must explain selection, hierarchy, continuity, or completion. No ambient drift, perpetual card movement, unsolicited haptics, or ancestor-level animation that catches unrelated state changes.

### Preserve stable interaction topology

Visual changes may alter fill, rim, opacity, small scale, and content hierarchy. They must not alter card frames during focus, remount navigation roots, duplicate focus ownership, or change transition-source IDs.

## 1. Shared Visual System

Extend `ReelFinTheme` with a small browse-specific token layer rather than scattering literals across screens.

### Color roles

- `editorialAccent`: restrained champagne for kickers, active indicators, and progress.
- `editorialPrimaryText`: near-white for titles and primary labels.
- `editorialSecondaryText`: stable secondary contrast for metadata and synopses.
- `editorialGlassTint`: low-opacity warm-neutral tint for grouped glass controls.
- `editorialFocusedRim`: subtle champagne-white blend for tvOS focused media.
- `editorialOpaqueFallback`: dark elevated surface used when Reduce Transparency is enabled.

The global application tint does not become champagne. System semantics, selection contrast, and primary buttons stay legible in all artwork contexts.

### Typography roles

- editorial kicker: uppercase or small caps, compact, high tracking;
- hero identity: server logo when available, otherwise a balanced title with a stable maximum size;
- section heading: strong but smaller than the current oversized iPhone headings;
- metadata: concise, secondary, and never visually equal to the title;
- supporting synopsis: Dynamic Type-compatible on iOS with bounded line counts in collapsed states.

### Shape roles

- one continuous radius family for media cards;
- a larger continuous radius for grouped Liquid Glass chrome;
- capsules only for compact actions and filters;
- circular glass only for icon-only actions.

### Liquid Glass implementation rules

- Use one native `GlassEffectContainer` per adjacent control cluster when the platform API is available.
- Use stable glass identities for selection morphing; do not rebuild the container when selection changes.
- Prefer native interactive glass/button styles over custom animated blur overlays.
- Use the opaque editorial fallback under Reduce Transparency.
- Keep poster artwork outside the glass container so image invalidation does not rebuild the control material.

## 2. Motion System

| Interaction | Normal motion | Reduced motion |
| --- | --- | --- |
| Hero page change | 0.20–0.22 s opacity plus very small scale | 0.18 s crossfade |
| Button press | 0.08–0.10 s opacity/scale feedback | opacity only |
| tvOS focus | 0.16 s ease-out, role-specific scale and fixed-radius shadow | 0.18 s ease-out, scale capped at 1.02 |
| Detail entry | existing native zoom continuity | 0.18 s crossfade |
| Header collapse | scroll-derived, quantized state | discrete compact/expanded state |
| Image reveal | 0.18–0.22 s opacity | immediate or short crossfade |

Rules:

- A hero timer advances only while the scene is active, VoiceOver is not driving the interface, Reduce Motion is off, and the user is not interacting.
- Automatic hero changes never trigger haptics. Haptics are reserved for direct user paging or activation.
- No animation changes blur radius, large shadow radius, or full-screen drawing groups per frame.
- New delayed work must be owned by a cancelable task and use latest-wins identity.

## 3. Home

### iOS Home

Preserve the existing `TabView`, navigation stacks, cache-first rows, actions, and rail ordering.

Refresh the hero composition:

- editorial kicker above the identity;
- server logo first, balanced text title fallback;
- one concise metadata line;
- grouped Play, Favorite, and More actions in a clean Liquid Glass cluster;
- champagne active-page indicator;
- quieter, consistent scrims that preserve title contrast without crushing artwork;
- no unsolicited haptic when the timer advances.

Refresh rails without changing data:

- landscape Continue Watching retains immediate progress and episode context;
- poster rails use a consistent radius, spacing, and metadata hierarchy;
- section-forward affordances become compact glass controls instead of oversized chevrons;
- skeletons match final geometry to prevent layout shifts.

### tvOS Home

Preserve native `Button` activation, one focus owner, row-qualified IDs, explicit focus handoff, inline Detail mounting, and the existing warmup coordinator.

The focused media surface gains:

- a restrained tonal lift;
- a subtle champagne-white rim;
- a fixed-radius shadow;
- the existing role-specific scale;
- no layout reflow or extra per-focus full-screen artwork request.

The top navigation and hero actions use grouped native Liquid Glass. Resting media cards stay artwork-only.

## 4. Library and Search

### Query correctness before visual polish

Library intents become genuinely latest-wins. Search, filter, sort, and initial reload share one owned task/generation. An older cache or network completion cannot overwrite newer criteria, and a criteria change is not discarded merely because pagination is running.

This behavior receives a deterministic failing regression test before production changes.

### iOS composition

- Start with an expanded editorial header containing title, result context, filters, and search.
- Collapse to a compact pinned Liquid Glass control row after meaningful scroll progress.
- Do not keep the full search/title/filter panel permanently over the poster wall.
- Keep the native search-role tab and current navigation ownership.
- Maintain a lazy grid with stable domain identity and unchanged selection semantics.

### tvOS composition

- Keep the current control bar, grid geometry, top-row routing, and exact poster restoration.
- Apply grouped Liquid Glass to active filter/sort controls, not to every poster.
- Use the shared media focus surface for the focused poster only.
- Remove artificial activation delay; press feedback occurs concurrently with immediate selection.

## 5. Detail

### Render-cost correction

The selected iOS carousel entry must not render two independent hero-grade background stacks. Only the selected item receives the sharp/full hero treatment. Neighbor previews use a deliberately cheaper artwork path with no hero-grade blur stack.

Large shadow radius does not vary continuously with scroll. Scroll-derived presentation values are isolated from the full Detail tree and quantized where a continuous value is not visually necessary.

### iOS composition

- Preserve native zoom entry and occurrence-qualified transition IDs.
- Retain the artwork-first top stage and horizontal context carousel.
- Group Back, Share, More, Play, Favorite, and completion actions into clean role-appropriate glass surfaces.
- Use logo-first identity, concise metadata, readable synopsis, and clearer separation between primary content and supporting rows.
- Keep episodes, cast, related items, and file details lazy and below the hero stage.

### tvOS composition

- Preserve inline Detail hosting, deterministic Play-first focus, event-driven dismissal, and exact source restoration.
- Apply Glass+ to hero action groups and the currently focused supporting control only.
- Keep all visible focus cues within fixed geometry.
- Non-actionable cast content must not masquerade as actionable focus targets; either expose a real action or remove it from the focus graph.

## 6. Artwork Delivery and Loading UI

### Canonical variants

Use `ArtworkRequestProfile` as the source of truth for poster, landscape card, logo, preview, and hero request widths/qualities. A speculative request and its visible consumer must resolve to the same canonical URL when they represent the same role.

All speculative artwork prefetch goes through `DefaultImagePipeline`. Do not fetch-and-discard image bytes through a separate shared URL session.

### Bounded work

- Limit prefetch fan-out and decode concurrency.
- Preserve in-flight URL deduplication and per-consumer cancellation.
- Give visible/focused work priority over speculative work.
- Stop speculative work when the owning item, focus scope, screen, or generation changes.

### Stale-publication protection

`CachedRemoteImage` validates request identity/generation after every suspension point, including memory/disk hits and fallback attempts. A reused cell cannot publish an older image after its content identity changes.

### Loading presentation

- iOS shimmer is shared or bounded to the first visible loading window rather than one perpetual animation per cold grid cell.
- Reduce Motion uses a static tonal placeholder.
- Image errors keep stable final geometry and display a quiet fallback; they do not collapse rails or trigger root loading states.
- Existing authenticated token headers, sanitized persistent cache keys, off-main ImageIO downsampling, and memory-cost accounting remain unchanged.

## 7. State and Component Boundaries

Add or extract small, testable units rather than adding more state to the existing large screen roots:

- `HeroRotationPolicy`: pure eligibility and next-page policy.
- `EditorialMotion`: duration and Reduce Motion values.
- `EditorialGlassRole`: navigation, action cluster, compact control, and focused-media roles.
- shared logo-first media identity view with text fallback.
- shared tvOS focused media surface using existing `TVMotion.FocusRole` geometry.
- `ArtworkVariantResolver`: maps `ArtworkRequestProfile` to canonical visible/prefetch URLs.
- owned Library query coordinator/generation inside `LibraryViewModel`.
- isolated and quantized Home/Detail scroll presentation state.

Views receive narrow value inputs. Artwork fetching, sorting, filtering, formatting, and policy decisions do not run inside hot `body` builders.

## 8. Data Flow

### Browse and artwork

```text
cached Home/Library model
  -> lazy visible row/cell
  -> canonical artwork role/profile
  -> authenticated DefaultImagePipeline
  -> memory hit | disk hit + off-main decode | bounded network + decode
  -> identity-checked image publication
  -> short accessible reveal
```

### tvOS focus

```text
native FocusState changes once
  -> constant-time visual focus derivation
  -> cancel previous warmup scope
  -> settle current candidate
  -> bounded canonical artwork/playback warmup
```

Visual focus feedback is immediate and does not wait for warmup or network completion.

### Library intent

```text
search/filter/sort intent
  -> cancel/replace owned generation
  -> cache result if still current
  -> remote result if still current
  -> one stable grid update per accepted phase
```

## 9. Error Handling and Accessibility

- Logged-out launch and authenticated cache-first Home behavior remain unchanged.
- A failed hero logo falls back to the media title without delaying the rest of the hero.
- Artwork failures retain layout and may retry only through explicit lifecycle/identity changes, not an unbounded loop.
- Library errors are scoped to the active criteria generation.
- Reduce Motion, Reduce Transparency, VoiceOver, Dynamic Type, Increased Contrast, and tvOS couch-distance readability are explicit validation states.
- Hidden or decorative artwork is removed from accessibility traversal.
- Every focusable/tappable element performs a real action and has a stable label/identifier where UI automation depends on it.
- Glass foreground contrast is validated over bright and dark artwork.

## 10. Test-Driven Implementation

Production behavior changes follow red-green-refactor cycles. At minimum, add failing tests first for:

1. hero auto-rotation eligibility and automatic-haptic exclusion;
2. Library latest-intent-wins behavior across blocked cache/network and pagination overlap;
3. canonical prefetch/visible URL equality for each artwork role;
4. bounded prefetch/decode concurrency;
5. cancelled/reused cached image requests not publishing stale images;
6. Reduce Motion/Reduce Transparency motion and glass-role policies;
7. constant Detail preview/hero artwork cost policy;
8. immediate tvOS Library activation with unchanged focus provenance;
9. fixed focus geometry and exact Home/Library Detail return.

Existing Home, Library, Detail, image-pipeline, navigation, focus, playback launch, and root-auth tests remain regression gates.

## 11. Simulator and Performance Validation

### Deterministic gates

- `xcodegen generate`
- targeted new policy and regression tests after each red-green cycle
- ImageCache and Jellyfin image URL suites
- Home/Library/Detail action and layout suites
- tvOS polish/navigation/focus suites
- complete `ReelFin` iOS test scheme
- complete `ReelFinTV` tvOS test scheme
- `git diff --check`

### iOS Simulator journeys

Use the configured iPhone 17 simulator on iOS 26.3.1:

- cold and warm authenticated Home launch;
- manual and automatic hero paging, including background/foreground and Reduce Motion;
- fast Home rail scrolling before and after images are warm;
- rapid search typing, filter changes, sort changes, and pagination overlap;
- Library poster-wall scroll with expanded-to-compact header transition;
- Home and Library entry into Detail and exact return;
- Detail carousel paging, fast scroll, episodes, cast, and related rows;
- image failure/fallback, VoiceOver labels, larger text, Reduce Motion, and Reduce Transparency;
- screenshots of Home, compact Library header, and Detail over both bright and dark artwork.

### tvOS Simulator journeys

Use Apple TV 4K (3rd generation) on tvOS 26.2:

- traverse Home landscape and poster rails rapidly;
- prove one stable focus transition per directional input;
- activate focused cards immediately without a fixed press delay;
- traverse Library controls, every first-row position, and multiple grid rows;
- open Detail from Home and Library and return to the exact source;
- confirm Play remains initial Detail focus;
- exercise Reduce Motion and Reduce Transparency;
- capture focused/resting card pairs and bright/dark hero contexts;
- launch and dismiss playback from the redesigned browse surfaces to prove route isolation.

### Comparative performance evidence

Capture the same Release interactions before and after relevant phases:

- SwiftUI body-update counts and long updates;
- Animation Hitches/Core Animation hitch count and duration;
- Time Profiler samples around ImageIO, SwiftUI layout, blur, and main-thread work;
- peak decoded-image memory and texture growth;
- image request count, bytes, source, dedupe, cancellation, and decode queue wait through existing/extended signposts.

Simulator timings are comparative evidence, not a claim about physical-device thermals. Any regression in launch, focus acquisition, playback startup, or cache behavior blocks completion.

## 12. Implementation Order

1. Add failing policy/regression tests and shared editorial/motion/glass tokens.
2. Canonicalize and bound artwork prefetch/decode; fix stale image publication and loading presentation.
3. Refresh Home hero, rails, carousel policy, and tvOS focused surface.
4. Correct Library latest-wins behavior, then implement expanded/compact iOS header and tvOS Glass+ controls.
5. Reduce Detail background/preview/scroll cost, then apply the editorial Glass+ composition.
6. Run platform-specific targeted tests and simulator visual journeys after each surface.
7. Run full iOS/tvOS gates, comparative performance captures, and playback-entry regression checks.
8. Record measured results and any simulator limitations in `PLANS.md` and `OPTIMIZATION_AUDIT.md`.

## Acceptance Criteria

- Home, Library/Search, and Detail visibly share the approved Cinematic Editorial Glass+ language.
- Liquid Glass is more present and recognizably Apple-native without covering resting artwork or multiplying live glass across grids.
- iOS and tvOS navigation structures and interaction semantics remain unchanged.
- Hero auto-rotation is accessible, interruptible, and produces no automatic haptic.
- Rapid Library intents cannot publish stale results.
- Visible and speculative artwork use canonical variants through the authenticated pipeline.
- Fast scrolling/focus traversal does not create unbounded prefetch or decode work.
- Reused cells cannot publish stale cached images.
- iOS Detail no longer duplicates hero-grade background work for the selected entry or neighboring previews.
- tvOS card activation is immediate and exact focus restoration remains deterministic.
- Reduce Motion and Reduce Transparency produce polished fallbacks.
- The configured iOS and tvOS simulator builds, tests, UI journeys, and final regression gates complete without release-blocking failures.
- `PLANS.md` and `OPTIMIZATION_AUDIT.md` contain the final performance and validation evidence.
