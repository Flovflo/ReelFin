# Expired Session Recovery Design

## Status

Approved in conversation on August 9, 2026. This specification covers only the expired-session/Home-zombie P0. Security remediations and release automation remain separate, independently reviewable work items.

## Context

`JellyfinAPIClient` invalidates the persisted Jellyfin session after a `401 Unauthorized` only when the rejected request still belongs to the active token. That token-generation guard correctly prevents a stale request from signing out a newly authenticated session.

`RootViewModel`, however, reads authentication state only during `bootstrap()`, explicit login, and explicit sign-out. When a current authenticated request receives `401`, the API actor clears the token and session while the root UI remains authenticated. Cached Home content stays visible and later operations fail with `Please login first` until the app is relaunched. This is the release-blocking Home-zombie state.

## Goals

- Move the root UI to the login flow immediately after the active API session is invalidated.
- Preserve the existing stale-request guard: a late `401` from an old token must never invalidate or hide a newer session.
- Keep logged-out and cached authenticated launch behavior unchanged.
- Keep the mechanism actor-safe, cancelable with the root view lifecycle, and free of polling or fixed sleeps.
- Make the behavior deterministic in unit tests without requiring a live Jellyfin server.

## Non-Goals

- Refresh tokens or silently reauthenticate; Jellyfin access tokens do not provide a repository-supported refresh flow here.
- Clear the configured server when authentication expires.
- Change Home cache loading, playback recovery, onboarding, or Quick Connect behavior.
- Add a global notification bus for unrelated application state.

## Chosen Architecture

The API boundary exposes a typed `AsyncStream<SessionInvalidationEvent>` through `JellyfinAPIClientProtocol`. The concrete client owns a private thread-safe broadcaster, and each read of `sessionInvalidations` creates an independently cancelable stream subscription. The actor emits an event only when an authenticated request invalidates the current session. A default protocol implementation returns an already-finished stream so existing focused fakes remain source-compatible unless a test needs to drive invalidation.

`RootViewModel` gains one long-running async lifecycle method. It acquires a fresh subscription, bootstraps current state, then consumes that subscription. Each event marks bootstrap complete and sets `isAuthenticated` to `false` on the main actor. `ReelFinRootView` runs that method from its existing `.task`, so SwiftUI cancellation removes only that subscription when the root view disappears or is replaced. A recreated `.task` reads the property again and receives a new live subscription on the same API client.

This approach is preferred over `NotificationCenter` because the event stays typed and scoped to the injected API dependency, and over polling because invalidation is immediate and creates no background wakeups.

## Event Semantics

`SessionInvalidationEvent` carries a reason value, initially `.unauthorized`. The event deliberately carries no token, server URL, username, user ID, response body, or signed URL.

The actor emits exactly once for a `401`-driven transition from an existing active session to no session. Explicit user sign-out does not emit this unauthorized event: `RootViewModel.signOut()` continues to update the UI directly, so its user-visible transition is deterministic and not dependent on stream scheduling. Calling either path while already signed out remains idempotent.

The existing request-token comparison remains the authority for `401` races:

1. A request captures token A.
2. The user authenticates and installs token B.
3. The request for token A later returns `401`.
4. Because the active token is B, the actor neither signs out nor emits an event.

For a `401` belonging to the current token, the actor clears session persistence and Keychain state, synchronously broadcasts one invalidation event before its first `await`, and then cancels deduplicated work.

The broadcaster assigns each subscription an opaque process-local identifier and stores only its continuation. `onTermination` removes that continuation under a lock. Broadcasting snapshots the current continuations under the lock and yields after releasing it, so subscriber termination cannot deadlock emission. Canceling or dropping one stream never finishes the broadcaster or any future stream, and no event payload or subscriber state contains credentials or server data.

## Root Lifecycle

The root lifecycle method performs bootstrap before listening for events. The stream property is nonisolated and creates a buffered subscription synchronously, so an event cannot be lost between acquiring that subscription and entering iteration. The root captures a fresh stream before awaiting bootstrap, then consumes it afterward.

When SwiftUI cancels the lifecycle because the root disappears, the stream's termination handler unregisters only that lifecycle subscriber. The client broadcaster remains live. If the root reappears with the same dependencies, the new `.task` calls `runRootLifecycle()` again, obtains a new subscription, and receives subsequent invalidations normally.

Before hiding authenticated UI for an event, the root re-reads `currentSession()`. If a newer login completed after the event was emitted but before it was consumed, the root ignores the obsolete event. This second guard prevents stream-delivery scheduling from signing out a replacement session without putting token or user data in the event.

When invalidated, the root does not recreate dependencies, clear cached metadata, or erase server configuration. SwiftUI replaces the authenticated shell with the existing login flow. A successful subsequent login calls the existing `completeLogin(_:)` path and restores authenticated UI state.

Review demo mode remains isolated: its preview API uses the default finished stream and cannot be signed out by production network activity.

## Error Handling and Privacy

- Stream termination is a normal lifecycle condition and shows no error.
- Cancellation exits observation promptly, unregisters only the canceled subscriber, and leaves future subscriptions available.
- Unauthorized errors still propagate to the initiating feature so it can stop its own loading state.
- No credential or media metadata enters the event or application logs.
- The UI uses the existing login copy; this change adds no raw server error text.

## Test Strategy

Tests follow strict red-green-refactor cycles.

### API actor tests

- A current-session `401` clears the session and yields exactly one `.unauthorized` event.
- Canceling one consumer and subscribing again on the same client leaves the replacement consumer able to receive a later `.unauthorized` event.
- A stale `401` arriving after a new authentication leaves the new session active and yields no event.
- A public unauthenticated request returning `401` does not invalidate an existing session and yields no event.
- Repeated sign-out while already signed out does not emit duplicate invalidations.

### Root model tests

- An authenticated root consuming an invalidation event becomes unauthenticated without relaunch.
- Bootstrap still authenticates when both a session and server configuration exist.
- Logged-out bootstrap still completes without a root spinner.
- Canceling the lifecycle task stops its observation without disabling a later lifecycle subscription on the same client.
- Completing a new login after invalidation restores authenticated state.

### Integration and release checks

- Reproduce the original real-server symptom with an expired token and verify the login flow replaces cached Home instead of leaving a zombie shell.
- Authenticate again, browse Home and Search, open metadata, start playback, and exercise player controls on iOS.
- Repeat authentication, browsing, and playback smoke coverage on tvOS.
- Run the complete iOS and tvOS test suites before release archive and TestFlight upload.

## Compatibility and Rollout

The change adds no dependency and preserves the public behavior of existing API operations. Protocol fakes remain compatible through a default finished stream. Broadcaster identifiers and streams are process-local and do not alter persisted formats, App Store privacy declarations, Jellyfin server state, or playback reporting.

The release is acceptable only when the focused red-green tests, complete simulator suites, real-server smoke tests, and release archive checks all pass. Simulator evidence validates routing and behavior but does not prove physical-device HDR or Dolby Vision rendering.
