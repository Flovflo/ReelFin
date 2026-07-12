# tvOS UX Polish Final Fixes Report

Date: 2026-07-12

Worktree: `/Users/flo/Documents/Projet/ReelFin/.worktrees/tvos-ux-polish`

Branch: `codex/tvos-ux-polish`

Baseline: `66343dd3895f65b8834b09a39c848ba5d8dd9b4f`

Implementation commit: `f7c38ea` (`fix(tvos): preserve Home detail return provenance`)

## Outcome

- Home Detail presentation now stores an immutable origin (`featured` or one row ID), the presented rail snapshot, the displayed carousel item, and the resolved return item.
- A carousel neighbor is resolved in the original rail before any fallback. Duplicate media on Hero or another row cannot change provenance.
- If the displayed target disappears, the nearest surviving snapshot item in the same rail is selected deterministically; ties prefer the earlier snapshot position. No other rail is consulted.
- Row focus restoration continues to use one exact row-qualified `rowID::itemID` focus value. Hero is used only for Hero-origin presentations. iOS presentation branches were not changed.
- `TVMotionFocusModifier` now selects the approved 0.28-second/0.80-bounce spring normally and a 0.18-second ease-out under Reduce Motion. Library activation scale is 1.025.
- Resume choice layout now uses 16-point button spacing and a tokenized 32-point question size.
- The two trailing spaces in the approved tvOS design were removed. `.superpowers/sdd/progress.md` contains one Task 6 line and was returned to its pre-wave tracked state, so it is not part of the implementation commit.

## TDD Evidence

RED, provenance/navigation:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:PlaybackEngineTests/TVUXPolishNavigationTests \
  -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests
```

Result: `** TEST FAILED **` at compile time because `TVHomeDetailPresentationContext` and `TVHomeDetailReturnTargetResolver` did not exist. This proved the duplicated-item/original-row tests were RED before production implementation.

RED, motion/resume metrics isolated from the navigation test source:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests \
  EXCLUDED_SOURCE_FILE_NAMES=TVUXPolishNavigationTests.swift
```

Result: `** TEST FAILED **` because `questionFontSize`, `libraryActivationScale`, and `TVFocusAnimationMetrics` were absent.

GREEN, final deterministic TVUX and Home gate:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:PlaybackEngineTests/TVUXPolishNavigationTests \
  -only-testing:PlaybackEngineTests/TVUXPolishLayoutTests \
  -only-testing:PlaybackEngineTests/DefaultSyncEngineHomeFeedTests \
  -only-testing:PlaybackEngineTests/HomeCardTransitionSourceTests \
  -only-testing:PlaybackEngineTests/HomeViewModelActionTests \
  -only-testing:PlaybackEngineTests/HomeViewModelFeedEnrichmentTests
```

Result: `** TEST SUCCEEDED **`; 38 tests executed, 0 failures, 0 unexpected, 0 skips. XCTest execution was 0.386 seconds and the Xcode test operation was 57.064 seconds.

Breakdown:

- `TVUXPolishNavigationTests`: 13/13.
- `TVUXPolishLayoutTests`: 8/8.
- Home-related suites: 17/17.

## Generation And Build

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodegen generate
```

Result: project generation succeeded. No target or dependency change was required in `project.yml`; unrelated generator-version scheme churn was not retained.

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build \
  -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A'
```

Result: `** BUILD SUCCEEDED **` on the required authenticated simulator after the final source state was established.

## Targeted UI Evidence

No existing ReelFinTV UI test drives a Detail carousel neighbor change. The closest lightweight available gate was run directly:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A' \
  -only-testing:ReelFinTVUITests/TVPlayerLiveUserJourneyTests/testHomeCardBackRestoresExactFocusAndKeepsAppForeground
```

Observed runs:

- First attempt: failed after a transient 8-second exact-focus timeout; Detail closed and ReelFin remained foreground.
- Diagnostic rerun: passed 1/1 in 16.845 seconds. Temporary non-sensitive diagnostics showed the target resolved and the owned handoff applied.
- Final rerun after removing all temporary diagnostics: passed 1/1 in 16.816 seconds.

The requested carousel-specific behavior is therefore covered by deterministic tests for duplicated media across two rows, explicit Hero-only origin, neighbor selection, removed-target nearest-survivor fallback, and exact row-qualified focus identity. No new heavy UI journey was added outside scope.

## Whitespace And Bookkeeping

```bash
git diff --check
git diff --check 17777cc..HEAD
```

Result: both exited 0 after implementation commit `f7c38ea`; the historical range now includes the design-spec whitespace correction.

```bash
rg -n '^Task 6:' .superpowers/sdd/progress.md
```

Result: exactly one Task 6 line at line 15.

## Interaction Auto-review

- Row source: selection captures `.row(id:)` plus the row item snapshot; carousel callbacks and dismissal re-resolve against that row only.
- Carousel: the displayed item is retained separately from the current fallback, so a disappearing target is resolved by snapshot distance at dismissal as well as on change.
- Hero: only `.featured` origin can read `featuredItemIDs` or produce a featured transition source.
- Focus: row restoration produces one `HomeCardTransitionSource.id(rowID:itemID:)` value, matching the card's `FocusState` identity. The existing latest-wins/cancelable handoff remains unchanged.
- iOS: new Home state and resolution integration are inside `#if os(tvOS)` paths; Resume and Library visual changes are also tvOS-only.
- Performance: resolution is O(rail size) only on carousel change/dismissal, with no network work, artwork work, timer, detached task, per-frame observation, or broader `MainActor` scope.

## Concerns

- One transient live focus timeout occurred before two consecutive passes. No behavior change was needed, so it is recorded as a simulator/UI-automation flake rather than hidden.
- There is no existing UI automation gesture for Detail carousel neighbor navigation. Deterministic provenance coverage is complete, but a future carousel-capable live fixture could add end-to-end proof without changing this implementation.
