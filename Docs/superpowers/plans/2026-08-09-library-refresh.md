# Home And Library Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a clean native pull-to-refresh flow to Search/Library while preserving the existing Home refresh behavior and latest-wins request guarantees.

**Architecture:** Reuse `StickyBlurHeader`'s native `.refreshable` hook. Home keeps its sync-backed refresh. Library gets a view-model operation that starts the current criteria request, cancels pagination/older criteria work through the existing generation mechanism, and exposes refresh state separately from page loading.

**Tech Stack:** SwiftUI, Swift concurrency, `@Observable`, XCTest, XcodeGen, iOS Simulator.

## Global Constraints

- Scope is iOS Home and Search/Library only; do not change Detail or tvOS behavior.
- Keep cached content visible while a refresh is in flight.
- Preserve latest-wins ownership and cancellation checks.
- Do not add third-party dependencies or fixed delays.
- Update `PLANS.md` and `OPTIMIZATION_AUDIT.md` after implementation.

---

### Task 1: Library refresh state and request semantics

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Library/LibraryViewModel.swift`
- Test: `Tests/PlaybackEngineTests/LibraryViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for `manualRefresh()` using the active filter/sort criteria and for cancellation of a suspended pagination request while the refreshed first page becomes authoritative.

- [ ] **Step 2: Run the tests and verify they fail**

Run the two new `LibraryViewModelTests` methods with `xcodebuild test`. The expected failure is the missing `manualRefresh()` API and refresh-state behavior.

- [ ] **Step 3: Implement the minimal view-model API**

Add `isRefreshing` and an async `manualRefresh()` that guards duplicate refreshes, calls `submitCriteria()`, awaits the returned task, and clears the state in `defer`. Keep existing request ownership and cached-first behavior.

- [ ] **Step 4: Run the tests and verify they pass**

Run the targeted Library tests and confirm no stale pagination response commits after refresh.

### Task 2: Connect the iOS Library UI

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Library/LibraryView.swift`
- Test: `Tests/ReelFinUITests/HomeAndDetailActionsUITests.swift` or the nearest existing Library UI test file if a refresh identifier is needed.

- [ ] **Step 1: Add the refresh action to the existing scroll container**

Pass `refreshAction: { await viewModel.manualRefresh() }` to the iOS `StickyBlurHeader` used by Library.

- [ ] **Step 2: Prevent duplicate footer loading UI during refresh**

Keep the existing page-loading footer for pagination, but hide it while `viewModel.isRefreshing` so the system refresh control is the single visible progress indicator.

- [ ] **Step 3: Run the Library tests and build**

Run the targeted tests and build the iOS scheme before touching documentation.

### Task 3: Documentation and final verification

**Files:**
- Modify: `PLANS.md`
- Modify: `OPTIMIZATION_AUDIT.md`

- [ ] **Step 1: Record the refresh behavior and validation evidence**

Document Home's sync-backed refresh, Library's criteria-preserving refresh, stale-request protection, and the exact test/build results.

- [ ] **Step 2: Run final checks**

Run `xcodegen generate`, targeted iOS tests, iOS/tvOS builds, and `git diff --check`. Report any existing compiler warnings separately from failures.
