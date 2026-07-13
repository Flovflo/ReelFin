# HTTP cancellation flake diagnosis

Date: 2026-07-13
Worktree: `/Users/flo/Documents/Projet/ReelFin/.worktrees/tvos-ux-polish`
HEAD: `761a445691e27df5acf723efdb41208770c90124`
Simulator: iPhone 17, `98D9A848-5303-487D-8379-1EB2A788FA06`
Developer directory: `/Applications/Xcode-beta.app/Contents/Developer`

## Status

**DIAGNOSED — test observation race, not a missing product cancellation.**

The exact test is highly flaky in a fast repeated XCTest host. Across two retry-free
100-iteration batches it failed 97/200 times (48.5%), always at line 154 with
`stopLoadingCount == 0` instead of `1`. An external temporary diagnostic copy of the test recorded
that `URLProtocol.stopLoading()` frequently occurs *after* `readTask.result` has become available.
The product has already initiated cancellation, but the test samples the separate asynchronous
URLProtocol callback before Foundation delivers it.

No tracked source was edited. The only worktree write made by this diagnosis is this ignored report.
Temporary diagnostic source and result artifacts were kept under `/tmp`.

## Scope read completely

- `Tests/PlaybackEngineTests/NativeMediaCore/HTTPRangeByteSourceTests.swift` (223 lines)
- `NativeMediaCore/Sources/NativeMediaCore/MediaAccess/HTTPRangeByteSource.swift` (163 lines)
- `NativeMediaCore/Sources/NativeMediaCore/MediaAccess/StreamingRangeWriter.swift` (320 lines)
- `NativeMediaCore/Sources/NativeMediaCore/MediaAccess/MediaByteSource.swift`
- Relevant cancellation ownership in `NativePlayerPlaybackController.swift`,
  `NativeMatroskaSampleBufferPlayerView.swift`, and `CachingMediaByteSource.swift`
- `StreamingRangeWriterTests.swift`
- Commit `f7767cb05a4bd1cf4586c38c321dd1f9ca10bad6`, its complete relevant patch and
  `.superpowers/sdd/task-2-report.md`
- The introducing commit `e429ee0a447b0308a22d770c83c7e0aa54f7c78e`
- Blame and relevant history through HEAD

## Exact reproduction

The fast repeated command was:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06' \
  -only-testing:PlaybackEngineTests/HTTPRangeByteSourceTests/testCancelStopsAnInFlightRangeExactlyOnce \
  -test-iterations 100 \
  -resultBundlePath /tmp/reelfin-http-cancel-100.xcresult
```

No `-retry-tests-on-failure` option was used. `-test-iterations` ran all requested repetitions and
reported each failure directly; it did not retry or mask failures.

### Results

| Run | Mode | Result | Failure rate |
| --- | --- | ---: | ---: |
| Exact batch 1 | Same test host, 100 iterations | 41 failed / 59 passed | 41.0% |
| Exact batch 2 | Same test host, 100 iterations | 56 failed / 44 passed | 56.0% |
| Exact combined | Same test host, 200 iterations | 97 failed / 103 passed | **48.5%** |
| Exact relaunch check | Relaunch test runner each iteration, 30 iterations | 0 failed / 30 passed | 0% |

Batch 1's failure iterations were:

```text
4,9,11,16,17,18,19,23,27,29,30,33,34,35,37,40,44,45,46,48,50,58,60,62,64,
68,69,70,71,75,77,78,81,83,84,85,88,92,94,96,98
```

Batch 2's failure iterations were:

```text
3,5,6,10,11,12,13,15,17,19,20,23,25,27,28,30,31,32,35,36,37,41,43,46,47,
48,50,53,54,56,57,59,61,62,64,66,67,68,69,70,75,76,77,78,79,81,82,83,84,
85,86,89,92,93,95,98
```

Every failure was the same observation:

```text
HTTPRangeByteSourceTests.swift:154: XCTAssertEqual failed: ("0") is not equal to ("1")
```

The relaunch check used `-test-iterations 30 -test-repetition-relaunch-enabled YES`. It passed,
but it materially slowed each test to about 51–56 ms, compared with roughly 1–3 ms in the original
fast batch. That result is consistent with the timing race: the extra scheduling/launch overhead
gives `stopLoading()` time to arrive. Relaunching would mask the flake; it is not a correction.

Raw artifacts:

- `/tmp/reelfin-http-cancel-100.log`
- `/tmp/reelfin-http-cancel-100.xcresult`
- `/tmp/reelfin-http-cancel-100-second.log`
- `/tmp/reelfin-http-cancel-100-second.xcresult`
- `/tmp/reelfin-http-cancel-relaunch-30.log`
- `/tmp/reelfin-http-cancel-relaunch-30.xcresult`

## Data flow and root cause

The current test does this:

```text
SuspendingRangeProtocol.startLoading()
  -> fulfill "started"
test calls await source.cancel()
  -> HTTPRangeByteSource.cancel()
     -> StreamingRangeWriter.invalidate()
        -> set invalidated = true under lock
        -> URLSession.invalidateAndCancel()
test awaits readTask.result
test immediately samples stopLoadingCount
```

The missing assumption is that awaiting the stream consumer also waits for
`SuspendingRangeProtocol.stopLoading()`. It does not.

`HTTPRangeByteSource.cancel()` is declared `async`, but its body only calls the synchronous
`rangeStreamer.invalidate()`. `StreamingRangeWriter.invalidate()` calls
`URLSession.invalidateAndCancel()`, which *initiates* cancellation. Foundation subsequently
delivers URLSession task completion and the URLProtocol teardown callback on its own asynchronous
queues.

`StreamingRangeWriter.urlSession(_:task:didCompleteWithError:)` finishes the stream continuation
when it sees `NSURLErrorCancelled`. That makes the `for try await` in
`HTTPRangeByteSource.fetch(range:)` end and allows `readTask.result` to become available. There is
no product or Foundation contract in these files that orders `URLProtocol.stopLoading()` before
that continuation completion.

The assertion at line 154 therefore compares a lock-safe value at an unsafe lifecycle point. The
counter itself is synchronized; the test has not synchronized with the event that changes it.

### Recorded event order

To confirm the ordering without touching tracked files, HEAD was exported with `git archive` to
`/tmp/reelfin-http-cancel-diag.s10yuB`. Only that external copy of the test added monotonic event
recording and alternative observation strategies. Product sources remained identical to HEAD.

Two 100-iteration condition/event probes recorded `stopLoading` relative to `readTask.result`:

| Temporary probe | `stopLoading` before read result | `stopLoading` after read result | Maximum observed post-result lag | Result |
| --- | ---: | ---: | ---: | ---: |
| Poll actual count until 1 | 44/100 | **56/100** | 229 microseconds | 100/100 passed |
| XCTest expectation fulfilled by `stopLoading` | 45/100 | **55/100** | 609 microseconds | 100/100 passed |

In the first probe, `stopLoading` was always after `cancel()` returned: 100/100 samples, by 78 to
2,252 microseconds (mean 179.8 microseconds). The `readResult` event itself recorded count `0` in
56/100 polling samples and 55/100 expectation samples. This directly reproduces the state sampled
by the failing assertion.

For runs where `stopLoading` followed `readTask.result`, observed positive lag was:

- polling probe: 7–229 microseconds, median 28 microseconds, p95 160 microseconds;
- expectation probe: 11–609 microseconds, median 63 microseconds, p95 239 microseconds.

Representative orders were both legal and observed:

```text
startLoading -> cancelReturned -> stopLoading -> readResult
startLoading -> cancelReturned -> readResult(count=0) -> stopLoading(count=1)
```

This is decisive evidence for an observation race. The transport does receive exactly one stop in
the condition/event probes; it is simply not guaranteed to have received it at line 154.

## History analysis

- `e429ee0a` introduced `testCancelStopsAnInFlightRangeExactlyOnce` and the dedicated
  `SuspendingRangeProtocol`.
- `f7767cb` did **not** change that cancellation test. It repaired a different test:
  completed closed ranges now distinguish a premature stop from Foundation's normal
  post-completion cleanup using per-instance completion state.
- `git diff f7767cb..HEAD` is empty for `HTTPRangeByteSourceTests.swift`,
  `HTTPRangeByteSource.swift`, and `StreamingRangeWriter.swift`.
- The `f7767cb` task report records single successful focused runs and two successful complete HTTP
  class runs after the completed-range instrumentation repair. Those passes are compatible with
  this intermittent race and did not stress the cancellation test with repetitions.

The current failure is therefore not evidence of a post-`f7767cb` production regression. It is a
latent timing assumption in the cancellation test that a fresh full gate happened to expose.

## Condition-based observation versus fixed sleeps

An external temporary test compared the real condition with three arbitrary delays after
`readTask.result`:

| Strategy | Requested delay | Actual measured delay after read result | Result |
| --- | ---: | ---: | ---: |
| Wait until locked `stopLoadingCount >= 1` | Event-dependent | Only until event | 100/100 passed |
| XCTest expectation fulfilled by `stopLoading` | Event-dependent | Only until event | 100/100 passed |
| Fixed sleep | 100 microseconds | 168–1,169 microseconds, mean 1,036 | 100/100 passed |
| Fixed sleep | 1 millisecond | 1,033–2,076 microseconds, mean 1,934 | 100/100 passed |
| Fixed sleep | 5 milliseconds | 5,083–7,719 microseconds, mean 7,006 | 100/100 passed |

The fixed sleeps happened to pass this sample, but they are not tied to the callback and their
actual delay overshot the requested duration substantially. A shorter sleep can still lose under
different scheduler load or Foundation versions; a longer sleep slows every run and still does not
establish a lifecycle contract. The event-based expectation is both faster and deterministic.

Raw temporary-probe artifacts:

- `/tmp/reelfin-http-condition-100.log`
- `/tmp/reelfin-http-condition-100.xcresult`
- `/tmp/reelfin-http-stop-expectation-100.log`
- `/tmp/reelfin-http-stop-expectation-100.xcresult`
- `/tmp/reelfin-http-fixed-delays-100.log`
- `/tmp/reelfin-http-fixed-delays-100.xcresult`

## Minimal TDD recommendation

Make a **test-only** synchronization correction; do not change `HTTPRangeByteSource` or
`StreamingRangeWriter` for this failure.

1. Add `SuspendingRangeProtocol.onStop`, reset it in `reset()`, and invoke it immediately after the
   lock-protected counter increment in `stopLoading()`.
2. In `testCancelStopsAnInFlightRangeExactlyOnce`, create a `stopped` XCTest expectation before
   starting the read. Set `expectedFulfillmentCount = 1` and `assertForOverFulfill = true`.
3. Assign `onStop` to fulfill that expectation.
4. After `await source.cancel()` and `await readTask.result`, await the `stopped` expectation with a
   bounded timeout, then assert the locked count is exactly one.
5. Prove the test-only change with at least 100 `-test-iterations`, without retries. The external
   prototype of this exact event-driven shape passed 100/100.

Minimal shape:

```swift
let stopped = expectation(description: "range request stopped")
stopped.expectedFulfillmentCount = 1
stopped.assertForOverFulfill = true
SuspendingRangeProtocol.onStop = { stopped.fulfill() }

await source.cancel()
_ = await readTask.result
await fulfillment(of: [stopped], timeout: 1)

XCTAssertEqual(SuspendingRangeProtocol.stopLoadingCount, 1)
```

This preserves the test's intended assertion—an in-flight transport is stopped once—while waiting
for the event actually under test. Do not add `Task.sleep`.

## Concerns and boundaries

1. **`cancel()` is initiation, not a transport-quiescence barrier.** The protocol declares an
   async method, but `HTTPRangeByteSource.cancel()` returns after calling
   `invalidateAndCancel()`, before `URLProtocol.stopLoading()` necessarily runs. That is normal for
   the current implementation and is not the cause of a missed cancellation. If higher-level code
   requires `await source.cancel()` to guarantee complete URLSession invalidation, that would be a
   separate product-contract change requiring its own failing lifecycle test and likely a session
   invalidation completion signal.
2. **The current `readTask.result` is not asserted.** `StreamingRangeWriter` intentionally finishes
   quietly for `NSURLErrorCancelled`, so an explicitly cancelled empty range can currently appear as
   a successful empty/partial read. Whether that is desired for a top-level byte source is a
   separate semantic question; this flake does not establish it as a defect.
3. **Strict mathematical “exactly once” needs a defined observation endpoint.** Waiting for the
   first stop event and asserting count one is the minimal practical correction and removes the
   present race. If the test must prove no arbitrarily late second callback can ever occur, product
   or test infrastructure needs an explicit session-invalidated/quiescent event; no finite sleep
   can prove that negative.
4. **Current teardown can race the late callback.** On a fast failure, XCTest may enter `tearDown`
   and reset the static double while Foundation is still delivering `stopLoading()`. Waiting for
   the stop event before test completion also removes that potential cross-test contamination.
5. **Relaunching or slowing tests is not a fix.** The 30/30 relaunch pass changed the timing by an
   order of magnitude and should not be used to declare the original assertion stable.

## Implemented test-only correction (2026-07-13)

Status: **GREEN**.

The confirmed minimal correction was applied only to
`Tests/PlaybackEngineTests/NativeMediaCore/HTTPRangeByteSourceTests.swift`:

- `SuspendingRangeProtocol` now exposes a lock-protected `onStop` callback;
- `reset()` clears that callback under the same lock as the counter;
- `stopLoading()` increments the counter and captures the callback under the lock, then invokes the
  callback outside the lock;
- the cancellation test creates a one-shot XCTest expectation, enables over-fulfillment checking,
  and awaits the stop event before sampling `stopLoadingCount`.

No production source, fixed sleep, retry option, or test-runner slowdown was added.

### Fresh RED

Before the correction, the exact fast repeated test was run 30 times:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06' \
  -only-testing:PlaybackEngineTests/HTTPRangeByteSourceTests/testCancelStopsAnInFlightRangeExactlyOnce \
  -test-iterations 30 \
  -resultBundlePath /tmp/reelfin-http-cancel-red-30.xcresult
```

Result: **TEST FAILED**, exit 65. Executed 30 tests with 17 failures and 13 passes
(56.7% failure rate). Every failure was the expected line-154 observation:

```text
XCTAssertEqual failed: ("0") is not equal to ("1")
```

Artifacts: `/tmp/reelfin-http-cancel-red-30.log` and
`/tmp/reelfin-http-cancel-red-30.xcresult`.

### Focused GREEN

After the test-only correction, the exact single test passed:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06' \
  -only-testing:PlaybackEngineTests/HTTPRangeByteSourceTests/testCancelStopsAnInFlightRangeExactlyOnce \
  -resultBundlePath /tmp/reelfin-http-cancel-green-focused.xcresult
```

Result: **TEST SUCCEEDED**. Executed 1 test with 0 failures.

### Retry-free 100-iteration GREEN

The original fast-host reproducer was then repeated 100 times, with no retry option:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06' \
  -only-testing:PlaybackEngineTests/HTTPRangeByteSourceTests/testCancelStopsAnInFlightRangeExactlyOnce \
  -test-iterations 100 \
  -resultBundlePath /tmp/reelfin-http-cancel-green-100.xcresult
```

Result: **TEST SUCCEEDED**. Executed 100 tests with 0 failures in 0.171 seconds of test time.

Artifacts: `/tmp/reelfin-http-cancel-green-100.log` and
`/tmp/reelfin-http-cancel-green-100.xcresult`.

### Complete HTTP range class GREEN

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild test \
  -project ReelFin.xcodeproj \
  -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06' \
  -only-testing:PlaybackEngineTests/HTTPRangeByteSourceTests \
  -resultBundlePath /tmp/reelfin-http-range-class-green.xcresult
```

Result: **TEST SUCCEEDED**. Executed 6 tests with 0 failures.

The only warning in the focused build output was the existing App Intents metadata-skip warning:

```text
warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

`git diff --check` was clean after the correction. `.superpowers/sdd/progress.md` remained
untouched and unstaged by this work.

## Conclusion

Product cancellation is being issued and the transport stop arrives exactly once in synchronized
observations. The gate failure is caused by line 154 reading a thread-safe counter before the
asynchronous `URLProtocol.stopLoading()` callback has arrived. The minimal justified change is an
event-driven test wait, with no production modification and no fixed delay.
