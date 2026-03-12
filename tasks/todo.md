## Session Plan

### Context
- Mandatory project control files referenced by `AGENTS.md` are missing: `progress.txt`, `IMPLEMENTATION_PLAN.md`, `LESSONS.md`, `PRD.md`, `APP_FLOW.md`, `TECH_STACK.md`, `DESIGN_SYSTEM.md`, `FRONTEND_GUIDELINES.md`, `BACKEND_STRUCTURE.md`.
- Available documentation used for this audit: `AGENTS.md`, `project.yml`, `Docs/Playback-Architecture-Current.md`, and the current tvOS/iOS SwiftUI source tree.
- Working tree is already dirty in multiple source files. Session changes must avoid reverting unrelated user edits.

### Goals
1. Decouple tvOS detail navigation from playback initialization.
2. Redesign browse/detail/show surfaces toward a premium Apple TV-like editorial layout.
3. Introduce phased loading, focus-driven prefetch, and aggressive caching without blocking first paint.
4. Add instrumentation for tap-to-detail, hero image, metadata, play readiness, and first frame.

### Planned Execution
1. Baseline audit
- Map current navigation, detail loading, playback startup, image loading, and fetch lifecycles.
- Identify duplicate requests, `task`/`onAppear` loops, main-thread image decode risks, and focus gaps.

2. Architecture refactor design
- Define `DetailSceneModel` phased loading states.
- Define repository/cache/prefetch/warmup responsibilities and ownership boundaries.
- Define reusable tvOS hero, action cluster, and editorial rail components.

3. Test-first changes
- Add unit tests for phased detail loading, request coalescing, playback warmup separation, and prefetch cancellation/deduping.
- Add targeted view-model tests for instant shell availability and non-blocking warmup.

4. Source implementation
- Refactor home/detail/library flows to navigate instantly with lightweight item snapshots.
- Add background/backdrop system with blurred expansion, scrims, and progressive image transitions.
- Add focus-driven prefetch coordinator and short-lived playback warm cache.
- Remove autoplay/bootstrap coupling from detail appearance path.

5. Validation
- Run targeted tests first, then broader tvOS build/test validation as feasible.
- Review no-regression surface for Home, Library, Detail, and Playback entry points.
- Produce change log, untouched areas, concerns, and follow-up cleanup candidates.

### Known Risks To Resolve During Implementation
- Existing uncommitted changes overlap with the same files this refactor will touch.
- Missing product/design docs mean any visual choice must be inferred from current code and the user’s reference requirements.
- Current app target names and shared modules mirror iOS/tvOS code, so refactors must preserve both platforms where sources are shared.
