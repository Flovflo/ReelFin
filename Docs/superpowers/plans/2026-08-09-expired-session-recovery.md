# Expired Session Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the authenticated Home shell with the existing login flow as soon as the current Jellyfin session is invalidated by `401 Unauthorized`, without allowing stale requests or delayed events to hide a newer login.

**Architecture:** `JellyfinAPIClient` exposes a token-free, re-subscribable `AsyncStream<SessionInvalidationEvent>` backed by a private thread-safe broadcaster and emits `.unauthorized` only for a current-token invalidation. `RootViewModel` owns one SwiftUI-scoped subscription per lifecycle run, rechecks cancellation, a main-actor authentication generation, and the current session before changing UI state, and remains cancelable through `.task(id: ObjectIdentifier(viewModel))` without disabling later subscriptions.

**Tech Stack:** Swift 6, Swift Concurrency actors and `AsyncStream`, SwiftUI Observation, XCTest, XcodeGen, iOS/tvOS simulator builds.

## Global Constraints

- Preserve the Apple-native playback path and existing module boundaries.
- Preserve the current-token comparison that prevents a stale `401` from invalidating a replacement session.
- Do not put tokens, usernames, user IDs, server URLs, or signed URLs in invalidation events or logs.
- Do not poll, add fixed sleeps to production code, broaden `MainActor`, or add third-party dependencies.
- Logged-out launch must still reach auth without a root spinner; authenticated launch must still paint cached Home before sync completes.
- All source edits start with a focused test that is observed failing for the expected missing behavior.
- Use `/Applications/Xcode-beta.app/Contents/Developer` for Xcode commands on this workstation.

---

## File Structure

- `Shared/Sources/Shared/Protocols.swift`: owns the cross-module event type and protocol surface.
- `JellyfinAPI/Sources/JellyfinAPI/JellyfinAPIClient.swift`: owns the re-subscribable event broadcaster and current-token invalidation emission.
- `ReelFinUI/Sources/ReelFinUI/RootViewModel.swift`: owns bootstrap plus session-event consumption and root auth state.
- `ReelFinUI/Sources/ReelFinUI/ReelFinRootView.swift`: scopes the lifecycle task to the current root-model identity.
- `ReelFinUI/Sources/ReelFinUI/PreviewMocks.swift`: accepts an injected stream or stream factory and a controllable session lookup in the existing preview/test API double without adding test-only methods to production classes.
- `Tests/JellyfinAPITests/JellyfinPlaybackReportingTests.swift`: proves API invalidation and stale-request behavior.
- `Tests/PlaybackEngineTests/RootViewModelAuthPersistenceTests.swift`: proves the user-visible root transition and delayed-event guard.

### Task 1: Typed API invalidation event

**Files:**
- Modify: `Shared/Sources/Shared/Protocols.swift`
- Modify: `JellyfinAPI/Sources/JellyfinAPI/JellyfinAPIClient.swift`
- Test: `Tests/JellyfinAPITests/JellyfinPlaybackReportingTests.swift`

**Interfaces:**
- Produces: `SessionInvalidationEvent: Sendable, Equatable`
- Produces: `JellyfinAPIClientProtocol.sessionInvalidations: AsyncStream<SessionInvalidationEvent>`
- Preserves: `JellyfinAPIClientProtocol.signOut() async`

- [ ] **Step 1: Write the failing current-session event test**

Add a test that captures the stream before issuing the existing authenticated request and expects one event after the `401`:

```swift
func testUnauthorizedResponseEmitsSessionInvalidation() async throws {
    let client = makeUnauthorizedClient()
    let received = expectation(description: "Current session invalidation")
    let consumer = Task {
        for await event in client.sessionInvalidations {
            XCTAssertEqual(event, .unauthorized)
            received.fulfill()
            return
        }
    }
    defer { consumer.cancel() }

    do {
        _ = try await client.fetchPlaybackSources(itemID: "movie-1")
        XCTFail("Expected the expired session to be rejected")
    } catch AppError.unauthenticated {}

    await fulfillment(of: [received], timeout: 1)
}
```

Extract only the repeated session/settings/token construction into `makeUnauthorizedClient()` inside the test file; keep `URLProtocolStub` as the real request boundary.

- [ ] **Step 2: Run the focused test and observe RED**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:JellyfinAPITests/JellyfinPlaybackReportingTests/testUnauthorizedResponseEmitsSessionInvalidation
```

Expected: compilation fails because `sessionInvalidations` and `SessionInvalidationEvent.unauthorized` do not exist. This is the expected missing-contract failure.

- [ ] **Step 3: Add the minimal protocol contract**

Add to `Protocols.swift`:

```swift
public enum SessionInvalidationEvent: Sendable, Equatable {
    case unauthorized
}

public protocol JellyfinAPIClientProtocol: AnyObject, Sendable {
    var sessionInvalidations: AsyncStream<SessionInvalidationEvent> { get }
    // existing methods remain unchanged
}

public extension JellyfinAPIClientProtocol {
    var sessionInvalidations: AsyncStream<SessionInvalidationEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
```

The default finished stream preserves existing fakes that do not participate in root-session tests.

- [ ] **Step 4: Implement re-subscribable current-session emission without an actor reentrancy race**

Keep the protocol property and make each concrete-client access return a new process-local subscription:

```swift
public nonisolated var sessionInvalidations: AsyncStream<SessionInvalidationEvent> {
    sessionInvalidationBroadcaster.subscribe()
}

private nonisolated let sessionInvalidationBroadcaster = SessionInvalidationBroadcaster()
```

The private `SessionInvalidationBroadcaster` uses a lock-protected dictionary of continuations keyed by opaque UUIDs. `subscribe()` creates a stream with `.bufferingNewest(1)`, registers its continuation, and removes only that continuation from `onTermination`. `yield(_:)` snapshots continuations under the lock and yields after releasing the lock. Canceling one consumer must not finish the broadcaster or streams created by later property reads.

Refactor clearing into a helper that performs all state and persistence mutation synchronously on the actor, broadcasts before its first `await`, then cancels deduplicated work:

```swift
private func invalidateCurrentSessionAsUnauthorized() async {
    guard activeSession != nil else { return }
    activeSession = nil
    settingsStore.lastSession = nil
    try? tokenStore.clearToken()
    sessionInvalidationBroadcaster.yield(.unauthorized)
    await deduplicator.cancelAll()
}
```

Keep explicit `signOut()` non-notifying and idempotent. In the authenticated request catch, call the invalidation helper only while `activeSession?.token == requestToken`.

- [ ] **Step 5: Run the focused test and observe GREEN**

Run the Step 2 command. Expected: `testUnauthorizedResponseEmitsSessionInvalidation` passes.

- [ ] **Step 6: Write stale and public-request non-emission tests**

Extend the existing stale and public `401` tests with an inverted XCTest expectation consuming `sessionInvalidations`:

```swift
let unexpected = expectation(description: "No session invalidation")
unexpected.isInverted = true
let consumer = Task {
    for await _ in client.sessionInvalidations {
        unexpected.fulfill()
        return
    }
}
defer { consumer.cancel() }

// existing stale/public request flow
await fulfillment(of: [unexpected], timeout: 0.15)
```

Name the tests so they catch removal of the current-token guard and accidental invalidation by public auth failures.

- [ ] **Step 7: Prove the negative tests fail against a deliberate mutation**

Temporarily remove the `activeSession?.token == requestToken` condition, run the stale test, and confirm the inverted expectation fails. Restore the condition immediately and rerun both negative tests to green.

- [ ] **Step 8: Prove cancellation permits a later subscription**

Add a focused test that starts and cancels a first `sessionInvalidations` consumer, awaits its completion, obtains a second stream from the same concrete client, then provokes a current-session `401`. The second consumer must receive `.unauthorized` within a one-second XCTest deadline. This catches replacement of the broadcaster with a single stored `AsyncStream`.

- [ ] **Step 9: Run the owning API test class**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:JellyfinAPITests/JellyfinPlaybackReportingTests
```

Expected: all tests in the class pass with zero failures.

- [ ] **Step 10: Commit the API event unit**

```bash
git add Shared/Sources/Shared/Protocols.swift \
  JellyfinAPI/Sources/JellyfinAPI/JellyfinAPIClient.swift \
  Tests/JellyfinAPITests/JellyfinPlaybackReportingTests.swift
git commit -m "fix(auth): emit current session invalidation"
```

### Task 2: Root lifecycle consumes invalidation

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/PreviewMocks.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/RootViewModel.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/ReelFinRootView.swift`
- Test: `Tests/PlaybackEngineTests/RootViewModelAuthPersistenceTests.swift`

**Interfaces:**
- Consumes: `JellyfinAPIClientProtocol.sessionInvalidations`
- Produces: `RootViewModel.runRootLifecycle() async`
- Preserves: `RootViewModel.bootstrap() async`, `completeLogin(_:)`, and `signOut()`

- [ ] **Step 1: Make the preview fake accept a real event stream**

Add a stored property and initializer parameter with a finished-stream default:

```swift
let sessionInvalidations: AsyncStream<SessionInvalidationEvent>

init(
    authenticated: Bool = true,
    sessionInvalidations: AsyncStream<SessionInvalidationEvent> = AsyncStream { $0.finish() },
    // existing overrides
) {
    self.sessionInvalidations = sessionInvalidations
    // existing initialization
}
```

Change `ReelFinPreviewFactory.dependencies(authenticated:apiClient:)` to accept `MockJellyfinAPIClient` unchanged; tests retain a reference to call the fake's real `signOut()`.

- [ ] **Step 2: Write the failing Home-zombie regression test**

```swift
func testRootLifecycleLeavesAuthenticatedShellAfterSessionInvalidation() async {
    let (events, continuation) = AsyncStream<SessionInvalidationEvent>.makeStream()
    let api = MockJellyfinAPIClient(authenticated: true, sessionInvalidations: events)
    let dependencies = ReelFinPreviewFactory.dependencies(authenticated: true, apiClient: api)
    let viewModel = RootViewModel(dependencies: dependencies)
    let lifecycle = Task { await viewModel.runRootLifecycle() }
    defer { lifecycle.cancel() }

    let didBootstrap = await waitUntil { viewModel.didBootstrap }
    XCTAssertTrue(didBootstrap)
    await api.signOut()
    continuation.yield(.unauthorized)
    continuation.finish()
    await lifecycle.value

    XCTAssertTrue(viewModel.didBootstrap)
    XCTAssertFalse(viewModel.isAuthenticated)
}
```

Production mutation caught: removing event consumption leaves `isAuthenticated == true`, reproducing the zombie shell.

- [ ] **Step 3: Run the root test and observe RED**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:PlaybackEngineTests/RootViewModelAuthPersistenceTests/testRootLifecycleLeavesAuthenticatedShellAfterSessionInvalidation
```

Expected: compilation fails because `runRootLifecycle()` does not exist.

- [ ] **Step 4: Implement the minimal cancelable lifecycle**

Add to `RootViewModel`:

```swift
func runRootLifecycle() async {
    let invalidations = dependencies.apiClient.sessionInvalidations
    await bootstrap()

        for await _ in invalidations {
            guard !Task.isCancelled else { return }
            let generation = authenticationGeneration
            let session = await dependencies.apiClient.currentSession()
            guard !Task.isCancelled else { return }
            guard authenticationGeneration == generation, session == nil else { continue }
            authenticationGeneration &+= 1
            withAnimation(.easeInOut(duration: 0.2)) {
                didBootstrap = true
                isAuthenticated = false
        }
    }
}
```

Bind the root view task to the model it mutates:

```swift
.task(id: ObjectIdentifier(viewModel)) {
    await viewModel.runRootLifecycle()
}
```

Each `runRootLifecycle()` invocation reads `sessionInvalidations` once before bootstrap and therefore owns one buffered subscription. Canceling the SwiftUI task unregisters only that subscription; if the root reappears with the same dependencies, the recreated task obtains a fresh live subscription from the client broadcaster. Replacing `viewModel`, including review-mode entry or exit, changes the task identity so SwiftUI cancels the lifecycle attached to the old model and subscribes the replacement model.

Before awaiting `currentSession()`, capture a local main-actor authentication generation. After the await, recheck `Task.isCancelled`, require the generation to remain unchanged, and require the returned session to be `nil`. Do not suspend again between those guards and the unauthenticated-state mutation. Advance the generation on `completeLogin(_:)`, explicit sign-out intent, and each accepted invalidation so a concurrent auth transition makes an older event inert.

- [ ] **Step 5: Run the Home-zombie test and observe GREEN**

Run the Step 3 command. Expected: pass.

- [ ] **Step 6: Write the delayed-event/new-login guard test**

Buffer an `.unauthorized` event before starting the lifecycle while the fake still has an authenticated session:

```swift
func testRootLifecycleIgnoresInvalidationWhenReplacementSessionExists() async {
    let (events, continuation) = AsyncStream<SessionInvalidationEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let api = MockJellyfinAPIClient(authenticated: true, sessionInvalidations: events)
    continuation.yield(.unauthorized)
    continuation.finish()
    let dependencies = ReelFinPreviewFactory.dependencies(authenticated: true, apiClient: api)
    let viewModel = RootViewModel(dependencies: dependencies)
    await viewModel.runRootLifecycle()

    XCTAssertTrue(viewModel.didBootstrap)
    XCTAssertTrue(viewModel.isAuthenticated)
}
```

Production mutation caught: removing the `currentSession() == nil` recheck makes the delayed event hide a valid replacement session.

Add a bounded test-only helper using `ContinuousClock` (one-second deadline plus `Task.yield()`) for the bootstrap observation. Production code remains free of sleeps and polling.

- [ ] **Step 7: Prove the guard test fails against the mutation, then restore**

Temporarily remove the current-session recheck, run only the guard test, confirm failure, restore the guard, and rerun it to green.

- [ ] **Step 7a: Prove lifecycle replacement and actor-hop races**

Add bounded tests that cancel one lifecycle and start another on the same client, cancel while a controllable `currentSession()` lookup is suspended, and call `completeLogin(_:)` while that lookup is suspended. The replacement lifecycle must receive the next invalidation, while both stale suspended lookups must leave the current authenticated UI unchanged.

- [ ] **Step 8: Run all root persistence tests**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:PlaybackEngineTests/RootViewModelAuthPersistenceTests
```

Expected: authenticated bootstrap, logged-out bootstrap, complete login, current invalidation, and delayed-event tests all pass.

- [ ] **Step 9: Commit the root lifecycle unit**

```bash
git add ReelFinUI/Sources/ReelFinUI/PreviewMocks.swift \
  ReelFinUI/Sources/ReelFinUI/RootViewModel.swift \
  ReelFinUI/Sources/ReelFinUI/ReelFinRootView.swift \
  Tests/PlaybackEngineTests/RootViewModelAuthPersistenceTests.swift
git commit -m "fix(auth): exit zombie home after expired session"
```

### Task 3: Project and regression verification

**Files:**
- Verify: `project.yml`
- Verify: generated `ReelFin.xcodeproj`
- Update only if behavior or commands changed: `PLANS.md`, `OPTIMIZATION_AUDIT.md`

**Interfaces:**
- Consumes: completed Task 1 and Task 2 commits.
- Produces: a generated, buildable project with focused auth regressions passing on iOS and tvOS compilation.

- [ ] **Step 1: Regenerate the project**

```bash
xcodegen generate
```

Expected: exit 0 and no missing source or duplicate-file error.

- [ ] **Step 2: Run the combined focused auth tests**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test \
  -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:JellyfinAPITests/JellyfinPlaybackReportingTests \
  -only-testing:PlaybackEngineTests/RootViewModelAuthPersistenceTests
```

Expected: zero failures.

- [ ] **Step 3: Build the tvOS product to catch shared-protocol regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build \
  -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.5'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Review the final diff and hot-path constraints**

```bash
git diff --check main...HEAD
git diff --stat main...HEAD
git status --short
```

Confirm no fixed sleep, polling, token-bearing event, unrelated playback change, or generated/local artifact is tracked.

- [ ] **Step 5: Record performance documentation only if required**

This auth-state change does not add hot-path launch, sync, focus, playback, or artwork work beyond one suspended stream subscriber and lock operations limited to subscription, termination, and invalidation emission. If review finds a measurable hot-path impact, document it in `PLANS.md` and `OPTIMIZATION_AUDIT.md`; otherwise leave both files unchanged and state why in the delivery report.
