# Task 2 Report — Cancel byte sources and quiesce render queues

## Status

DONE_WITH_CONCERNS

The implementation and its focused lifecycle tests are complete. The Matroska teardown tests, the
probe-source test, the complete `NativePlayerConfigurationTests` class, and the requested
10-iteration seek loop passed. A final complete `HTTPRangeByteSourceTests` rerun and fresh iOS/tvOS
build gates could not be completed because Xcode stopped making progress before test launch. Those
limits are recorded below and are not reported as passing.

## Outcome

- Explicit replacement invalidates callback ownership before any reader cancellation.
- The playback task owns its byte source and awaits `source.cancel()` exactly once on every path
  after source creation.
- The restart coordinator cancels and awaits the previous playback task before starting a new
  source, keeping the observed maximum concurrent reader count at one.
- Renderer request callbacks are stopped, submitted video/audio work is drained with queue-safe
  `sync` barriers, then both renderers and sample queues are flushed.
- `stopPlayback` no longer moves the reader to `idle` synchronously. It retains a retirement task;
  the generation remains `retiring` until the cooperative reader cleanup completes.
- The temporary source used by `NativePlayerPlaybackController.prepare` is closed through one
  async success/error cleanup wrapper after probing, demux selection, and planning.
- Dismantle invalidates callback ownership synchronously, so queued diagnostics/progress callbacks
  cannot be delivered after dismantle while cooperative cleanup continues.

## Root cause

`startPlayback` and `stopPlayback` previously called `prepareForReaderReplacement` immediately.
That method cancelled tasks and flushed renderers without awaiting the playback task. The byte
source was local to `openDemuxAndPump` and was never cancelled. `stopPlayback` then called
`finishReaderRetirement` immediately, advertising `idle` while the reader could still be blocked
inside an async source read or could still have work submitted to the render queues.

`NativePlayerPlaybackController.prepare` likewise created an `HTTPRangeByteSource` (or caching
wrapper), used it for probe/demux/planning, and returned or threw without closing it.

## Design and ordering

`retireActiveGeneration()` is the single replacement/stop coordinator:

1. mark the current generation `retiring` and invalidate callback ownership;
2. stop renderer media-data requests and cancel the playback task;
3. await the playback task, whose final async path awaits `source.cancel()` and clears its owned
   `(generation, source)` pair;
4. mark the reader finished and release the generation;
5. drain `videoQueue`, then `audioQueue`;
6. flush renderers and clear sample queues.

The recorded order asserted by the test is:

```text
generationInvalidated
sourceCancelled
readerFinished
videoQueueQuiesced
audioQueueQuiesced
renderersFlushed
```

Each render queue is tagged with a queue-specific key. The main-thread teardown helper checks that
it has not re-entered either queue before calling `sync`, with an assertion and playback log for a
contract violation. No detached task and no second fire-and-forget source cancellation were added.

Natural EOF/failure still preserves the Task 1 contract: it enters `retiring`, is not seekable, and
retains callback ownership until explicit teardown. Its source is already cancelled exactly once by
the completing playback task; explicit retirement observes that completed cancellation rather than
calling `cancel()` again.

## TDD evidence

### RED

After adding the lifecycle, source, callback, and probe tests before production changes:

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06' \
  -only-testing:PlaybackEngineTests/NativePlayerConfigurationTests/testMatroskaReplacementCancelsSourceAndQuiescesBeforeRendererFlush \
  -only-testing:PlaybackEngineTests/NativePlayerConfigurationTests/testNativePlaybackPreparationCancelsTemporaryProbeSource \
  -only-testing:PlaybackEngineTests/HTTPRangeByteSourceTests/testCancelStopsAnInFlightRangeExactlyOnce
```

Result: **TEST FAILED**, exit 65. After removing async-autoclosure mistakes from the new tests, the
remaining failures were exactly the absent Task 2 interfaces:

```text
NativeMatroskaSampleBufferPlayerController has no member maximumConcurrentReaderCount
NativeMatroskaSampleBufferPlayerController has no member teardownEvents
NativeMatroskaSampleBufferPlayerController has no member callbackCountAfterDismantle
extra argument byteSourceFactory in call
```

### Focused GREEN

The same three tests passed after the implementation:

```text
Executed 3 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

This run proved the exact teardown ordering, first and second source cancellation count of one,
maximum concurrent reader count of one, zero callbacks after dismantle, temporary probe-source
cancellation, and one transport `stopLoading` for one HTTP source cancellation.

### Configuration lifecycle class

The first full class run exposed one intentionally obsolete Task 1 assertion that expected
`stopForDismantle()` to make the EOF reader `idle` synchronously. It failed 29/30 with:

```text
XCTAssertEqual failed: ("retiring") is not equal to ("idle")
```

The test was updated to wait conditionally for cooperative retirement. The fresh rerun passed:

```text
Executed 30 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

### Repeated seek gate

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06' \
  -only-testing:PlaybackEngineTests/NativePlayerConfigurationTests/testMatroskaForwardSeekKeepsCurrentReaderAndCoalescesRequest \
  -only-testing:PlaybackEngineTests/NativePlayerConfigurationTests/testMatroskaAlternatingSeekKeepsOnlyLatestTarget \
  -test-iterations 10
```

Result:

```text
Executed 20 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

## HTTP test isolation and incomplete final gate

The first combined complete HTTP/lifecycle gate ran nine tests. All three lifecycle/stop/track
tests passed, and five of six HTTP tests passed. The historical
`testCompletedClosedRangeDoesNotCancelTransportTask` observed a `stopLoading` callback left by the
new cancellation test because both tests shared one global `URLProtocol` double.

The cancellation scenario was moved to a dedicated `SuspendingRangeProtocol`, restoring isolation
instead of changing production transport behavior. After that correction, Xcode repeatedly stopped
before launching tests:

- existing DerivedData: no progress after `PruneExplicitPrecompiledModules` for more than 120 s;
- rebooted iPhone 17 simulator: the same pre-test stall;
- fresh `/tmp/reelfin-task2-derived`: no progress while creating/checking out Swift packages for
  more than 180 s.

Those sessions were terminated. Therefore the isolated complete `HTTPRangeByteSourceTests` class
is **not claimed as green**. The isolated test code did compile through test target linking before
the first pre-launch stall.

## Other verification

- `xcodegen generate` to `/tmp/reelfin-task2-xcodegen/ReelFin.xcodeproj`: succeeded.
- `git diff --check`: clean before staging.
- Focused test builds linked the iOS app and changed frameworks, but no separate fresh final iOS
  build is claimed.
- No fresh tvOS build completed after Task 2 and none is claimed.
- Observed non-source warnings were the existing App Intents metadata-skip warning and an Xcode
  diagnostic-collection `xcrun simctl` path error. No new Swift concurrency or queue warning was
  observed in completed runs.

## Files changed

- `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativeMatroskaSampleBufferPlayerView.swift`
- `PlaybackEngine/Sources/PlaybackEngine/NativePlayer/NativePlayerPlaybackController.swift`
- `Tests/PlaybackEngineTests/NativeMediaCore/NativePlayerConfigurationTests.swift`
- `Tests/PlaybackEngineTests/NativeMediaCore/HTTPRangeByteSourceTests.swift`
- `.superpowers/sdd/task-2-report.md` (ignored progress artifact, force-staged as explicitly requested)

## Self-review

- Scope is limited to the four Task 2 files plus this report; no project, dependency, generated
  project, playback engine, or unrelated worktree file is changed.
- The live Matroska default remains `HTTPRangeByteSource(url:headers:)` and playback stays Apple
  native.
- A created playback source has one owner and one call site for `await source.cancel()`.
- A probe/planning source has one cleanup wrapper with symmetric success/error cancellation.
- No new detached task exists. Synchronous UIKit dismantle starts or reuses a retained retirement
  task; source cancellation itself remains inside the playback task awaited by that coordinator.
- Callback invalidation happens synchronously before dismantle returns; `idle` happens only after
  the playback task and source cancellation finish.
- Queue barriers cannot run from either tagged render queue and occur before renderer flush.
- Replacement awaits complete source cleanup and render quiescence before `beginPlayback`, so a new
  reader cannot overlap the retired reader.
- Task 1 EOF/failure ownership semantics are preserved until explicit retirement.
- The one unresolved concern is verification infrastructure, not a silently ignored test failure:
  complete HTTP and final platform build gates are explicitly left for an independent clean Xcode
  run.

## Follow-up — HTTP completion instrumentation and final gates (2026-07-11)

### Status

DONE

The remaining HTTP test defect was isolated to test instrumentation. No production source was
changed in this follow-up.

### Root-cause evidence and RED

On Xcode 27.0 beta (`27A5209h`), Foundation may call `URLProtocol.stopLoading()` after a request has
already completed normally through `urlProtocolDidFinishLoading(_:)`. A standalone transport probe
recorded the sequence `completion bytes=4 error=nil`, followed by `stopCount=1`. Therefore a raw
`stopLoadingCount == 0` assertion cannot distinguish premature cancellation from Foundation's
normal post-completion cleanup.

The historical test was run alone on the iOS 27.0 iPhone 17 simulator:

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06' \
  -only-testing:PlaybackEngineTests/HTTPRangeByteSourceTests/testCompletedClosedRangeDoesNotCancelTransportTask
```

Result: **TEST FAILED**, exit 65, one test with one failure:

```text
XCTAssertEqual failed: ("1") is not equal to ("0")
```

This reproduces the invalid assertion independently; the failure is not cross-test contamination.

### Test correction

`MockRangeProtocol` now keeps lock-protected completion state per protocol instance and increments a
thread-safe counter only when `stopLoading()` arrives before normal completion is signalled. The
replacement test also reads two closed ranges sequentially from the same `HTTPRangeByteSource` and
asserts both payloads, proving the source remains usable after the first completed read.

`testCancelStopsAnInFlightRangeExactlyOnce` and its dedicated `SuspendingRangeProtocol` remain in
place unchanged. That test continues to assert exactly one transport stop for explicit in-flight
`cancel()`.

### GREEN verification

The complete `HTTPRangeByteSourceTests` class was run twice independently on iOS 27.0:

```text
run 1: Executed 6 tests, with 0 failures (0 unexpected)
run 2: Executed 6 tests, with 0 failures (0 unexpected)
```

The complete Task 2 configuration/lifecycle class also passed:

```text
NativePlayerConfigurationTests: Executed 30 tests, with 0 failures (0 unexpected)
```

This includes source cancellation and renderer-quiescence ordering, temporary probe-source
cancellation, stop/dismantle lifecycle, and track replacement coverage.

### Platform gates

- `xcodegen generate`: succeeded.
- `ReelFin` build, Xcode 27.0 / iPhone 17 simulator, iOS 27.0: **BUILD SUCCEEDED**.
- `ReelFinTV` build, Xcode 27.0 / Apple TV 4K (3rd generation) simulator, tvOS 27.0:
  **BUILD SUCCEEDED**.

The generated project rewrite was not retained because the requested follow-up scope is limited to
the HTTP test and this report. The only observed warnings were existing App Intents metadata-skip
messages and simulator/media-framework diagnostics; no new compiler error or test failure remained.
