# tvOS Player Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a crash-resistant, resumable, Apple-style tvOS player and prove it through real
remote-driven journeys on the tvOS simulator and Apple TV Flo against the live Jellyfin server.

**Architecture:** Preserve AVKit and ReelFin's Apple-framework sample-buffer routes. Put the
Matroska reader, byte source, callbacks, and renderer teardown behind one generation-owned
latest-wins lifecycle, then expose stable UI evidence to a new tvOS UI-test target.

**Tech Stack:** Swift 6 language mode 5, SwiftUI, UIKit, AVFoundation, AVKit, NativeMediaCore,
XCTest/XCUITest, XcodeGen, `xcodebuild`, `simctl`, `devicectl`.

## Global Constraints

- Keep playback Apple-native; add no third-party media engine or private API.
- Preserve Direct Play, original Jellyfin bytes, authenticated headers, and HDR/Dolby Vision metadata.
- Never uninstall ReelFin, erase its container, reset, or sign out `Apple TV Flo`.
- Do not print credentials, API keys, complete item IDs, or signed playback URLs.
- Use the installed iOS/tvOS 27.0 simulators and physical `Apple TV Flo` (`00008110-000979961AE1401E`).
- New behavior follows red-green-refactor; pre-existing dirty worktree changes remain intact.
- Do not commit pre-existing user changes from overlapping files without reviewing the exact staged diff.

---

### Task 1: Make Matroska reader generations explicit and deterministic

**Files:**
- Create: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativeMatroskaPlaybackGeneration.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativeMatroskaSampleBufferPlayerView.swift`
- Modify: `Tests/PlaybackEngineTests/NativeMediaCore/NativePlayerConfigurationTests.swift`

**Interfaces:**
- Produces: `NativeMatroskaPlaybackGeneration`, `NativeMatroskaByteSourceFactory`.
- Guarantees: one phase (`idle`, `starting`, `active`, `retiring`) and one owning generation.

- [ ] **Step 1: Replace the timing-dependent forward-seek test with a controlled active generation**

Add a factory that records created sources and keeps reads suspended until cancellation:

```swift
private final class RecordingByteSourceFactory: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var sources: [BlockingByteSource] = []

    func make(url: URL, headers: [String: String]) -> any MediaByteSource {
        let source = BlockingByteSource(url: url)
        lock.withLock { sources.append(source) }
        return source
    }

    var sourceCount: Int { lock.withLock { sources.count } }
}

private actor BlockingByteSource: MediaByteSource {
    nonisolated let url: URL
    private(set) var cancelCount = 0
    private var cancelled = false

    init(url: URL) { self.url = url }

    func read(range: ByteRange) async throws -> Data {
        while !cancelled {
            try await Task.sleep(for: .milliseconds(20))
        }
        throw MediaAccessError.cancelled
    }

    func size() async throws -> Int64? { 16 * 1_024 * 1_024 }
    func cancel() async { cancelCount += 1; cancelled = true }
    func metrics() async -> MediaAccessMetrics { MediaAccessMetrics() }
}
```

Make the test `async`, wait for `controller.readerPhase == .active`, then issue a forward seek and
assert generation/source count stay unchanged. Add `600 → 480 → 700` and assert the final pending
target is 700.

- [ ] **Step 2: Run the tests and confirm RED**

Run:

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06' \
  -only-testing:PlaybackEngineTests/NativePlayerConfigurationTests/testMatroskaForwardSeekKeepsCurrentReaderAndCoalescesRequest \
  -only-testing:PlaybackEngineTests/NativePlayerConfigurationTests/testMatroskaAlternatingSeekKeepsOnlyLatestTarget
```

Expected: compile failure because the controller has no injected factory/reader phase, followed by
behavioral failure until active versus retiring readers are distinguished.

- [ ] **Step 3: Add the lifecycle state and factory**

Create:

```swift
import Foundation
import NativeMediaCore

typealias NativeMatroskaByteSourceFactory = @Sendable (
    _ url: URL,
    _ headers: [String: String]
) -> any MediaByteSource

struct NativeMatroskaPlaybackGeneration: Equatable {
    enum Phase: Equatable { case idle, starting, active, retiring }

    private(set) var id = 0
    private(set) var phase: Phase = .idle

    mutating func beginStart() -> Int { id += 1; phase = .starting; return id }
    mutating func markActive(_ candidate: Int) { if candidate == id { phase = .active } }
    mutating func beginRetirement() { if phase != .idle { phase = .retiring } }
    mutating func finishRetirement(_ candidate: Int) { if candidate == id { phase = .idle } }
    func owns(_ candidate: Int) -> Bool { candidate == id && phase != .idle }
    var canSeekInPlace: Bool { phase == .active }
}
```

Inject the live factory into the controller initializer:

```swift
init(byteSourceFactory: @escaping NativeMatroskaByteSourceFactory = {
    HTTPRangeByteSource(url: $0, headers: $1)
}) {
    self.byteSourceFactory = byteSourceFactory
    super.init(nibName: nil, bundle: nil)
}
```

Use `generation.canSeekInPlace` instead of `playbackTask != nil`; mark active only after demux open
and track/decoder setup succeeds.

- [ ] **Step 4: Run focused tests and confirm GREEN**

Expected: both tests pass repeatedly with `-test-iterations 10`; max source count remains one for
in-place forward seek.

- [ ] **Step 5: Review the diff without staging unrelated work**

```bash
git diff --check
git diff -- ReelFinUI/Sources/ReelFinUI/Player/NativePlayer Tests/PlaybackEngineTests/NativeMediaCore/NativePlayerConfigurationTests.swift
```

---

### Task 2: Cancel byte sources and quiesce render queues before replacement

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativeMatroskaSampleBufferPlayerView.swift`
- Modify: `PlaybackEngine/Sources/PlaybackEngine/NativePlayer/NativePlayerPlaybackController.swift`
- Modify: `Tests/PlaybackEngineTests/NativeMediaCore/NativePlayerConfigurationTests.swift`
- Modify: `Tests/PlaybackEngineTests/NativeMediaCore/HTTPRangeByteSourceTests.swift`

**Interfaces:**
- Consumes: `NativeMatroskaPlaybackGeneration`, `NativeMatroskaByteSourceFactory`.
- Produces: `retireActiveGeneration()`; every source receives `cancel()` exactly once.

- [ ] **Step 1: Add failing teardown-order tests**

Record lifecycle events and assert exact ordering:

```swift
XCTAssertEqual(
    await controller.teardownEvents,
    [.generationInvalidated, .sourceCancelled, .readerFinished,
     .videoQueueQuiesced, .audioQueueQuiesced, .renderersFlushed]
)
XCTAssertEqual(await firstSource.cancelCount, 1)
XCTAssertEqual(controller.maximumConcurrentReaderCount, 1)
XCTAssertEqual(controller.callbackCountAfterDismantle, 0)
```

Add a probe-source test that runs `NativePlayerPlaybackController.prepare` and asserts its temporary
source is cancelled after probe/demux selection.

- [ ] **Step 2: Run and verify RED**

Expected: source cancel count is zero and teardown ordering/counters do not exist.

- [ ] **Step 3: Own and close the active source inside the playback task**

Store `(generation, source)` when created. Refactor `openDemuxAndPump` so every return path reaches:

```swift
await source.cancel()
clearActiveByteSource(source, generation: generation)
```

The playback task must not complete until this cleanup finishes. The restart coordinator cancels
the task, awaits `previousTask.value`, and only then starts the next generation.

- [ ] **Step 4: Quiesce callbacks before flush**

Invalidate callback ownership first, call both `stopRequestingMediaData()` methods, then drain queue
work already submitted:

```swift
videoQueue.sync {}
audioQueue.sync {}
displayLayer.flushAndRemoveImage()
audioRenderer.flush()
videoSamples.removeAll()
audioSamples.removeAll()
```

Do not call `sync` from either render queue. Keep controller teardown on the main actor and add an
assertion/log if the queue-specific key indicates re-entry.

- [ ] **Step 5: Cancel the temporary probe source**

In `NativePlayerPlaybackController`, use one async cleanup path:

```swift
let source = sourceFactory.make(...)
do {
    let result = try await probe(source)
    await source.cancel()
    return result
} catch {
    await source.cancel()
    throw error
}
```

- [ ] **Step 6: Run repeated focused tests and confirm GREEN**

Run lifecycle, HTTP range, stop/dismantle, track-reload, and 10-iteration seek tests. Expected:
zero failures, cancel count one, max active readers one, no callbacks after dismantle.

---

### Task 3: Finish Continue/Restart and unify launch intent

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/PlaybackResumeChoiceView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Detail/DetailView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift`
- Modify: `Tests/PlaybackEngineTests/DetailViewModelActionTests.swift`
- Modify: `Tests/PlaybackEngineTests/TVDetailActionButtonLayoutTests.swift`

**Interfaces:**
- Produces: `PlaybackLaunchChoicePolicy`, explicit `PlaybackStartPosition` for every movie/episode launch.

- [ ] **Step 1: Add the missing cross-entry tests**

Assert movie Detail, episode card, Home Continue Watching, and Next Up all use the same policy:

```swift
XCTAssertEqual(PlaybackLaunchChoicePolicy.orderedChoices, [.resume, .restart])
XCTAssertEqual(PlaybackLaunchChoicePolicy.startPosition(for: .resume), .resumeIfAvailable)
XCTAssertEqual(PlaybackLaunchChoicePolicy.startPosition(for: .restart), .beginning)
XCTAssertFalse(PlaybackLaunchChoicePolicy.shouldPresentChoice(for: completedItem))
```

Add a cancellation test proving no player session or progress report starts.

- [ ] **Step 2: Run and confirm RED for entry points that bypass the policy**

- [ ] **Step 3: Route all entries through one launch intent**

Use an enum-backed presentation item rather than parallel booleans. Keep Continue as tvOS default
focus and make Menu cancel. Pass the selected `PlaybackStartPosition` unchanged into both player
routes.

- [ ] **Step 4: Run focused tests and confirm GREEN**

Expected: every entry-point test passes, no playback prepare call occurs before selection.

---

### Task 4: Complete the Apple-style tvOS chrome and focus behavior

**Files:**
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTransportOverlayView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTimelineView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/TrackPickerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerChromePresentation.swift`
- Modify: `Tests/PlaybackEngineTests/NativePlayerChromeLayoutTests.swift`
- Modify: `Tests/PlaybackEngineTests/NativeMediaCore/NativePlayerConfigurationTests.swift`

**Interfaces:**
- Produces: bottom chrome, focusable timeline, anchored Audio/Subtitles popover, deterministic Menu hierarchy.

- [ ] **Step 1: Add failing policy/layout tests**

Test `Menu` precedence (`popover → chrome → player`), focus restoration, timeline clamping, and that
normal chrome actions are exactly Audio/Subtitles/Video.

- [ ] **Step 2: Run tests and confirm RED**

- [ ] **Step 3: Implement native Liquid Glass composition**

Keep metadata and timeline in the lower gradient. Wrap adjacent focusable actions in one
`GlassEffectContainer`; use `.buttonStyle(.glass)` and no custom blur on controls. Keep diagnostics
behind the existing debug-only route, never in normal chrome.

- [ ] **Step 4: Implement focus without sleeps**

Use `@FocusState`, `@Namespace`, `.focusScope`, and `.defaultFocus`. Publish an explicit focus-return
token on dismissal rather than scheduling a fixed-delay request.

- [ ] **Step 5: Run layout/policy tests plus tvOS build**

```bash
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A'
```

Expected: build exit 0; screenshots show edge-to-edge video, one lower gradient, and right-side menu.

---

### Task 5: Add real tvOS remote-driven UI tests and media evidence

**Files:**
- Modify: `project.yml`
- Create: `Tests/ReelFinTVUITests/TVPlayerLiveUserJourneyTests.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/CustomPlayerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativeMatroskaSampleBufferPlayerView.swift`
- Modify: `ReelFinUI/Sources/ReelFinUI/Player/NativePlayer/NativePlayerTransportOverlayView.swift`

**Interfaces:**
- Produces: `ReelFinTVUITests`; accessibility evidence for video ready, audio rendered, and time advancing.

- [ ] **Step 1: Add the tvOS UI-test target in `project.yml`**

```yaml
  ReelFinTVUITests:
    type: bundle.ui-testing
    platform: tvOS
    deploymentTarget: "26.0"
    sources:
      - path: Tests/ReelFinTVUITests
    dependencies:
      - target: ReelFinTVApp
    settings:
      base:
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: WZ4CHJH7TA
        PRODUCT_BUNDLE_IDENTIFIER: com.reelfin.tv.ui.tests
        TEST_TARGET_NAME: ReelFinTVApp
```

Add `ReelFinTVUITests` to the `ReelFinTV` scheme test targets and regenerate with `xcodegen generate`.

- [ ] **Step 2: Write the failing remote journey**

```swift
func testResumeSeekToZeroTracksAndDismissal() throws {
    let app = XCUIApplication()
    app.launchEnvironment["REELFIN_LIVE_UI_TARGET_ITEM_ID"] = requiredItemID("TEST_MKV_ITEM_ID")
    app.launch()

    XCTAssertTrue(app.otherElements["detail_screen"].waitForExistence(timeout: 45))
    XCUIRemote.shared.press(.select)
    XCTAssertTrue(app.otherElements["playback_resume_choice"].waitForExistence(timeout: 5))
    XCUIRemote.shared.press(.select)

    XCTAssertTrue(app.otherElements["native_player_video_rendering_ready"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.otherElements["native_player_audio_rendering_ready"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.otherElements["native_player_playback_advancing"].waitForExistence(timeout: 30))

    XCUIRemote.shared.press(.playPause)
    XCUIRemote.shared.press(.playPause)
    for _ in 0..<16 { XCUIRemote.shared.press(.left) }
    XCTAssertTrue(app.otherElements["native_player_seek_target_zero"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.otherElements["native_player_playback_advancing"].waitForExistence(timeout: 30))

    XCUIRemote.shared.press(.menu)
    XCTAssertTrue(app.otherElements["detail_screen"].waitForExistence(timeout: 10))
}
```

- [ ] **Step 3: Run and confirm RED**

Expected: target/markers do not yet exist or the current focus flow cannot complete.

- [ ] **Step 4: Publish real renderer evidence**

Expose markers only after decoded video has been enqueued/displayed, audio buffers have been
enqueued, and playback time advances across two observations. Do not publish audio readiness from
track metadata alone.

- [ ] **Step 5: Add journeys for Restart, track changes, chrome hierarchy, and 10 launch/seek/dismiss loops**

Use `XCUIRemote` directions and buttons, attach screenshots after every phase, and fail on any
player error overlay, frozen time marker, missing audio/video evidence, or unexpected dismissal.

- [ ] **Step 6: Run on tvOS 27 simulator and confirm GREEN**

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A' \
  -only-testing:ReelFinTVUITests/TVPlayerLiveUserJourneyTests
```

---

### Task 6: Make live E2E device-safe and validate Apple TV Flo

**Files:**
- Modify: `scripts/run_reelfin_player_e2e.sh`
- Create: `scripts/run_tvos_player_user_journey.sh`
- Modify: `Tests/ScriptTests/test_player_runtime_log_cleanliness.py`

**Interfaces:**
- Produces: timestamped `.artifacts/tvos-player-e2e/<run>/` evidence; no uninstall/reset path.

- [ ] **Step 1: Add failing script tests**

Assert the tvOS device runner contains no `uninstall`, `erase`, auth reset argument, password echo,
or full signed URL output. Assert `--skip-ui` also skips deep-evidence checks that require UI logs.

- [ ] **Step 2: Run Python tests and confirm RED**

```bash
python3 -m unittest discover -s Tests/ScriptTests -p 'test_*.py'
```

- [ ] **Step 3: Implement the safe runner**

The runner must use:

```bash
TV_DEVICE_ID='00008110-000979961AE1401E'
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination "platform=tvOS,id=${TV_DEVICE_ID}" \
  -only-testing:ReelFinTVUITests/TVPlayerLiveUserJourneyTests
```

It may update-install through Xcode's test action, but must never call uninstall/erase or inject an
auth-reset launch argument. Capture `.xcresult`, screenshots, redacted logs, item-probe summaries,
first-frame/audio/time evidence, seek counts, and reader-generation counts.

- [ ] **Step 4: Run the simulator live Jellyfin gate**

Use tvOS 27 simulator, configured live credentials, MP4 and MKV item IDs, and at least three loops.
Expected: every journey passes; one active reader; video/audio/time evidence after every seek.

- [ ] **Step 5: Run the Apple TV Flo gate without deleting state**

First run a build-only destination check. Then run the UI journey against the already authenticated
app. If the device is locked/asleep/unreachable, record that external state and continue simulator
and live API validation; do not reset or re-pair it.

- [ ] **Step 6: Run real live probes and sustained playback**

```bash
REELFIN_E2E_IOS_DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=27.0' \
REELFIN_E2E_TVOS_DESTINATION='platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=27.0' \
scripts/run_reelfin_player_e2e.sh --loops 3 --sample-size 10
```

Expected: explicit item probes, resume reporting, benchmarks, deterministic tests, UI journeys,
runtime fatal scan, and tvOS build all pass. Restore Jellyfin resume state after every prepared test.

---

### Task 7: Profile, regress, and document evidence

**Files:**
- Modify: `PLANS.md`
- Modify: `OPTIMIZATION_AUDIT.md`
- Evidence: `.artifacts/player-e2e/`, `.artifacts/tvos-player-e2e/`, temp memgraphs.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: final measured release-gate report.

- [ ] **Step 1: Run project generation and full builds**

```bash
xcodegen generate
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,id=98D9A848-5303-487D-8379-1EB2A788FA06'
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,id=092D088B-6307-4EFB-AE53-2457C2EE7F1A'
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS,id=00008110-000979961AE1401E'
```

- [ ] **Step 2: Run targeted then full unit/UI suites**

Include launch/auth, Home, Library, playback policy, native configuration, track reload, stop
reporting, drop resilience, script tests, tvOS unit tests, and tvOS UI journeys.

- [ ] **Step 3: Capture memory evidence on the same simulator flow**

After ten launch/seek/dismiss loops, capture and summarize a memgraph. Investigate app-owned leaked
`URLSession`, `StreamingRangeWriter`, controller, task, or renderer objects with trace trees. Repeat
the identical flow after any leak fix and compare types/paths rather than total file size.

- [ ] **Step 4: Scan runtime logs**

Fail on fatal signals, Main Thread Checker, background CoreAnimation transactions, repeated reader
start bursts, `null buffer_manager`, stale-generation callbacks, decoder failure, frozen time, or
persistent buffering.

- [ ] **Step 5: Update performance documents**

Record exact commands, pass/fail counts, device/OS, MP4/MKV/HDR/DV route results, resume/restart,
8-minute-to-zero, track changes, sustained duration, memory evidence, and physical-display caveats.

- [ ] **Step 6: Final verification before any completion claim**

Re-run the full acceptance command set fresh, inspect exit codes and xcresults, and compare every
acceptance criterion in the design spec against evidence. Report any remaining hardware-only or
external-state limitation explicitly.
