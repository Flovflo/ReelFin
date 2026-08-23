# Home And Library Refresh Design

**Goal:** Provide a reliable native pull-to-refresh interaction on Home and Search/Library without blanking visible content or allowing stale requests to overwrite newer results.

**Scope:** iOS Home and Search/Library only. Detail and tvOS are unchanged.

## Design

Home already routes its `StickyBlurHeader` refresh action to `HomeViewModel.manualRefresh()`, which performs a manual sync and reloads the persisted feed. Search/Library uses the same reusable scroll/header component but currently has no refresh action. The implementation will connect that existing native `.refreshable` path to a new `LibraryViewModel.manualRefresh()` operation.

Library refresh will reuse the active search text, media filter, and sort mode. Starting a refresh increments the existing criteria generation, cancels an in-flight criteria request and pagination request, resets pagination, then awaits the new criteria request. Local cached results remain visible while the remote request runs; latest-wins ownership checks continue to reject stale responses. A separate `isRefreshing` state prevents the pagination footer spinner from appearing as a duplicate refresh indicator.

Errors continue to preserve the last committed results and use the existing logging behavior. The native refresh control owns its accessibility label, progress animation, cancellation, and completion timing.

## Verification

- Unit tests prove a manual Library refresh uses the active criteria and resets pagination.
- Unit tests prove refresh cancels a suspended pagination request and stale pagination cannot replace refreshed results.
- Existing Home refresh tests remain green.
- iOS targeted tests, `xcodegen generate`, and iOS/tvOS builds are required before handoff.
