# Build 17 Security Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all nine validated findings from scan `dbde6617-f731-4a48-8d76-fa5212d6fc0b`, remove the two known Swift concurrency warnings, and produce factual Build 17 release evidence without publishing.

**Architecture:** Put each control at its untrusted boundary: origin-bound auth state, checked HTTP/EBML ranges, loopback capability routes, bounded HLS/image work, privacy-safe diagnostics, and a single uv/secret-sanitizing runner boundary. Each scoped commit must prove an exploit RED, minimal GREEN, deliberate mutation failure, restored GREEN, and legitimate playback regressions.

**Tech Stack:** Swift compiler from Xcode 26.5, repository Swift language setting from `project.yml`, Swift concurrency, Network.framework, AVFoundation, Foundation/ImageIO, XCTest, Bash, isolated uv-managed Python 3.13, XcodeGen.

## Global Constraints

- Work on `codex/reelfin-release-hardening`; preserve commits `0d2dc5d` through `4c4803b` and all unrelated worker/user changes.
- `project.yml` is authoritative; regenerate `ReelFin.xcodeproj`, never hand-edit it.
- Use `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`; destinations are iPhone 17 iOS 26.5 and Apple TV 4K (3rd generation) tvOS 26.5.
- Python runs only through `/Users/flo/.local/share/reelfin-codex/uv/bin/uv` with `UV_PYTHON_INSTALL_DIR=/Users/flo/.local/share/reelfin-codex/uv/python` and `UV_CACHE_DIR=/Users/flo/.cache/reelfin-codex/uv`.
- Never expose a password, token, signed URL, or route capability in files, argv, logs, `.xcresult`, reports, commits, or retained environment files. Use stdin or an already-set ephemeral environment value and unset aliases on exit.
- Keep playback Apple-native, async work cancelable/session-scoped, and locks outside suspension points. No production fixed sleeps or silent fallbacks.
- For every task: capture targeted RED; implement the smallest correction; capture GREEN; weaken the named guard and prove failure; restore it; run regressions; `git diff --check`; commit only that task.
- This plan performs no GitHub push, Apple/TestFlight/App Store action, archive upload, or Jellyfin mutation.

---

### Task 1: Bind Quick Connect to its issuing origin

**Files:** Modify `JellyfinAPI/Sources/JellyfinAPI/JellyfinAPIClient.swift`; create `Tests/JellyfinAPITests/JellyfinQuickConnectOriginTests.swift`.

- [ ] **RED:** With persisted server A, initiate on B and record `/QuickConnect/Initiate`, `/Connect`, and `/Users/AuthenticateWithQuickConnect`. Add tests for B-only requests, no persisted switch before success, old-secret rejection, late-generation rejection, and atomic B/session persistence. Run `xcodebuild test ... -only-testing:JellyfinAPITests/JellyfinQuickConnectOriginTests`; expect A to receive the secret or pending-handshake symbols to be absent.
- [ ] **Minimum correction:** Add private `{generation, normalizedServerURL, secret}` pending state. Normalize scheme/host/default port/base path; reject userinfo/query/fragment. Poll/exchange only an exact current secret at its stored origin, recheck generation after every `await`, persist configuration/session/token together only on success, and invalidate pending state on newer initiation/sign-out.
- [ ] **GREEN:** Rerun the focused class, then `-only-testing:JellyfinAPITests`; username/password auth and P0 invalidation tests must remain green.
- [ ] **Mutation:** Select `configuration?.serverURL` during poll, then remove one post-suspension generation check; the cross-origin and late-response tests must fail independently. Restore and rerun GREEN.
- [ ] **Commit:** `git add JellyfinAPI/Sources/JellyfinAPI/JellyfinAPIClient.swift Tests/JellyfinAPITests/JellyfinQuickConnectOriginTests.swift && git diff --check && git commit -m "fix: bind Quick Connect to its origin"`.

### Task 2: Resolve hostile ranges without truncating valid AVPlayer requests

**Files:** Modify `PlaybackEngine/Sources/PlaybackEngine/MediaGateway/LocalMediaGatewayHTTP.swift` and `PlaybackEngine/Sources/PlaybackEngine/MediaGateway/LocalCacheHTTPServer.swift`; create `Tests/PlaybackEngineTests/LocalMediaGatewayHTTPRangeSecurityTests.swift`.

- [ ] **RED:** Cover `bytes=0-9223372036854775807`, `bytes=9223372036854775807-`, multi-range, `bytes=-0`, endpoints outside a 32-byte resource, plus valid `0-0`, `4-7`, `4-`, suffix, and a valid range larger than 16 MiB. Expect malformed/unsatisfiable input to reject without a trap and the large valid response to advertise and stream its complete resolved interval.
- [ ] **Minimum correction:** Parse semantic Int64 bounds without constructing `ByteRange`; after the real length is known, resolve a checked half-open Int64 interval within the resource. Build headers with checked arithmetic and stream the entire interval through the existing 4 MiB reads/1 MiB socket slices. Do **not** clamp, shorten, or reject a valid range merely because it exceeds 16 MiB.
- [ ] **GREEN:** Run the new class plus `LocalMediaGatewayServerTests` and `PlaybackDropResilienceTests`; assert response `Content-Length`, final byte, open-ended seek, suffix, keep-alive, and origin/cache paths.
- [ ] **Mutation:** Restore `end - start + 1`, remove the resource-bound check, then introduce a 16 MiB visible clamp; overflow, out-of-resource, and large-valid-range tests must each fail. Restore and rerun GREEN.
- [ ] **Commit:** Stage the two production files and the new test, run `git diff --check`, commit `fix: validate complete local playback ranges`.

### Task 3: Authorize loopback servers and choose capacity from AVPlayer evidence

**Files:** Create `PlaybackEngine/Sources/PlaybackEngine/LocalPlaybackServerSecurity.swift` and `Tests/PlaybackEngineTests/LocalPlaybackServerSecurityTests.swift`; modify `MediaGateway/LocalCacheHTTPServer.swift`, `HLS/LocalHLSServer.swift`, `PlaybackDropResilienceTests.swift`, and `HLS/LocalHLSServerTests.swift`.

- [ ] **RED:** Prove `.any` binding, arbitrary cache/HLS paths, stale/prefix/percent-encoded capabilities, and unbounded simulated connections currently pass. Add a configurable gate test that refuses `capacity + 1` and releases exactly once.
- [ ] **Evidence before default:** With admission disabled but a test-only peak counter enabled, run AVPlayer startup, metadata reads, keep-alive reuse, concurrent ranges, seek/reread, HLS playlist refresh, stop/replay on iOS 26.5; record observed peak and scenario in `OPTIMIZATION_AUDIT.md`. Choose the checked-in capacity only after this run, with explicit headroom, then make a regression assert every legitimate scenario stays below it.
- [ ] **Minimum correction:** Bind both `NWListener`s explicitly to `127.0.0.1`; generate 32 random bytes per session; require exact slash-delimited capability routes before any media work; rotate on restart; log route classes only; acquire the measured-capacity gate before task creation and track/cancel accepted sockets on stop/deinit.
- [ ] **GREEN:** Run the new security class, `PlaybackDropResilienceTests`, all HLS tests, and the measured legitimate-burst test. Unauthorized requests must not increment origin/demux counters.
- [ ] **Mutation:** Change authorization to `hasPrefix`, bind `.any`, then bypass the gate; corresponding route, endpoint, and over-capacity tests must fail. Restore and rerun GREEN.
- [ ] **Commit:** Stage only the listed files, `git diff --check`, commit `fix: authorize loopback playback servers`.

### Task 4: Bound and authorize synthetic HLS work

**Files:** Modify `PlaybackEngine/Sources/PlaybackEngine/HLS/SyntheticHLSSession.swift`, `HLS/LocalHLSServer.swift`, `Tests/PlaybackEngineTests/HLS/SyntheticHLSSessionTests.swift`, and `HLS/LocalHLSServerTests.swift`.

- [ ] **RED:** Request `segment_1000000.m4s`, malformed/negative/overflow routes, unadvertised segments, cache pressure, repeated advertised segments, and seek. Assert far-future input performs zero new demux/repackage work; retention stays within an injected byte/window budget; valid startup/reread/seek remain possible.
- [ ] **Minimum correction:** Anchor segment parsing; generation accepts only the next sequence and is driven only by bounded prefetch. Store fragment/duration metadata in one byte-bounded working set, advertise only its current measured window, serve only advertised cached sequences, reject a single oversize fragment, and reset generation/advertisement correctly on seek.
- [ ] **GREEN:** Run `SyntheticHLSSessionTests`, `LocalHLSServerTests`, `HLSManifestBuilderTests`, `CMAFSegmentTimelineBuilderTests`, and `NativePlayerSessionRoutingTests`; retain native MKV HLS startup and backward-seek controls.
- [ ] **Mutation:** Let HTTP call the generating method, disable eviction, then parse malformed routes as zero; no-work, byte-budget, and malformed-route tests must fail. Restore and rerun GREEN.
- [ ] **Commit:** Stage the four files, `git diff --check`, commit `fix: bound synthetic HLS segment work`.

### Task 5: Centralize checked Matroska/EBML bounds

**Files:** Modify `NativeMediaCore/Sources/NativeMediaCore/Demuxing/Matroska/EBMLReader.swift` and the Track, Cluster, Segment, Cue, SeekHead parsers plus `MatroskaDemuxer.swift`; modify `Tests/PlaybackEngineTests/NativeMediaCore/MatroskaParserTests.swift`.

- [ ] **RED:** Craft short parents containing oversized CodecPrivate, SimpleBlock, BlockGroup, Cues, SeekHead, Info, eight-byte VINT, and nested unknown-size elements. Require `EBMLError`, never a trap; keep valid codec-private, lacing, cues, streaming cluster, and seek fixtures.
- [ ] **Minimum correction:** Add one checked payload-range API validating Int conversion, overflow-reporting endpoint addition, parent/data containment, and forward progress. Route every nested slice/cursor through it; reject nested unknown sizes and allow only the top Segment to use an explicit enclosing end.
- [ ] **GREEN:** Require `rg -n 'payloadOffset\s*\+|Data\(data\[[^]]*payload|func payloadEnd' NativeMediaCore/Sources/NativeMediaCore/Demuxing/Matroska` to find no bypass, then run `MatroskaParserTests`, `NativePlayerConfigurationTests`, and native-player end-to-end tests.
- [ ] **Mutation:** Remove parent containment, then replace checked endpoint addition; nested-parent and overflow fixtures must fail/trap in the isolated class. Restore and rerun GREEN.
- [ ] **Commit:** Stage the Matroska directory and its test, `git diff --check`, commit `fix: validate nested Matroska bounds`.

### Task 6: Make URL diagnostics allowlist-only

**Files:** Modify `Shared/Sources/Shared/SettingsStore.swift`; modify `Tests/PlaybackEngineTests/PlaybackLoggingTests.swift`.

- [ ] **RED:** Log a URL containing userinfo, private path, fragment, unknown `opaque_signature`, known `token`, and an allowlisted functional key. Assert neither log projection contains any raw component/value or falls back to `absoluteString`; cache-key behavior remains unchanged.
- [ ] **Minimum correction:** Share one safe projection for both log forms: normalized origin, nonreversible 12-hex path correlation, allowlisted lowercased query names, and total count only. Invalid input returns `invalid-url`; cache identity uses its separate sanitizer.
- [ ] **GREEN:** Run `PlaybackLoggingTests`, then classify every logger match from `rg -n 'absoluteString|reelfinCacheKey' Shared/Sources PlaybackEngine/Sources ImageCache/Sources`.
- [ ] **Mutation:** Restore unknown query values or a raw URL fallback; the opaque-signature/invalid-URL tests must fail. Restore and rerun GREEN.
- [ ] **Commit:** Stage the two files, `git diff --check`, commit `fix: minimize URL diagnostics`.

### Task 7: Minimize media identities and bound deep evidence

**Files:** Modify `Shared/Sources/Shared/{Logging,DetailPresentationTelemetry,PlayerDeepEvidenceSink}.swift`, `PlaybackEngine/.../NativePlayerPlaybackController.swift`, `PlaybackSessionController.swift`, `ReelFinUI/.../NativePlayerView.swift`, `scripts/assert_player_deep_playback_evidence.py`, `Tests/PlaybackEngineTests/PlaybackLoggingTests.swift`, and `Tests/ScriptTests/test_player_deep_playback_evidence.py`; create `PlayerDeepEvidenceSinkTests.swift`.

- [ ] **RED:** Assert raw item/source/track/title values never appear in public templates or serialized evidence; correlation is stable only in-process and contains no raw prefix; evidence is off by default, owner-only under protected Caches, structured, newline-safe, deterministic to reset, and rotated at 1 MiB.
- [ ] **Minimum correction:** Replace public/raw identifiers with reused process-local HMAC correlations or private hashing; retain only operational categories/numbers. Replace free-form evidence appends with allowlisted structured records, protected Caches storage, restrictive mode, pre-append rotation, and no localized free text. Update evidence validation to session/route facts.
- [ ] **GREEN:** Run both Swift logging/evidence suites and, via isolated uv, `Tests.ScriptTests.test_player_deep_playback_evidence`; source-scan all `shortIdentifier`, public identity, and evidence append call sites.
- [ ] **Mutation:** Restore one public raw ID and disable rotation; privacy and size tests must fail. Restore and rerun GREEN.
- [ ] **Commit:** Stage only the listed diagnostic, validator, and test files; `git diff --check`; commit `fix: minimize playback diagnostics`.

### Task 8: Enforce uv-only, secret-safe QA execution

**Files:** Create `scripts/run_python_with_uv.sh`, `scripts/redact_xctest_activity.py`, `scripts/assert_no_secret_artifacts.py`, and `Tests/ScriptTests/test_secure_qa_runners.py`; modify `scripts/run_playback_qa_loop.sh`, `scripts/run_reelfin_player_e2e.sh`, all Python files reported by `rg -l '(^|[;&|[:space:]])python3?([[:space:]]|$)|^#!.*python' scripts Tests/ScriptTests`, and affected ScriptTests.

- [x] **RED:** With invented canaries, test `umask 077`, stdin/ephemeral-env input, env-file password-key rejection, `2>&1 | redact | tee` ordering with preserved `PIPESTATUS[0]`, no credentialed `.xcresult`, exact/URL-encoded artifact scan without echoing the match, cleanup/unset, and zero executable direct `python`/`python3` commands or system-Python shebang bypasses.
- [x] **Minimum correction:** Make the wrapper fail closed unless the isolated uv path and managed Python 3.13 are available. Route every active Python call through it; remove direct-execution system-Python shebangs/executable bits or replace the entry with an uv wrapper. Never put password/signed URL in argv/files; sanitize before persistence; scan retained text; delete transient secret state on every exit.
- [x] **GREEN:** Run `uv run --no-project --python 3.13 python -m unittest discover -s Tests/ScriptTests -p 'test_*.py'`; run static scans for executable Python calls, shebangs, credentialed result bundles, raw `tee`, and permissive artifact modes.
- [x] **Mutation:** Pipe raw XCTest output to `tee`, call `python3`, restore a system-Python shebang/executable bit, and retain a canary; ordering, uv-boundary, direct-exec, and scanner tests must fail. Restore and rerun GREEN.
- [x] **Commit:** Stage wrapper/redactor/scanner, both runners, mechanically affected Python metadata, and tests; `git diff --check`; commit `fix: sanitize credentialed QA artifacts`.

### Task 9: Bound artwork transport before decode

**Files:** Modify `ImageCache/Sources/ImageCache/DefaultImagePipeline.swift` and `Tests/ImageCacheTests/DefaultImagePipelineTests.swift`.

- [ ] **RED:** Inject a 1 KiB encoded limit and cover declared oversize, chunked oversize, non-image MIME, pixel multiplication/limit, cancellation, at-most-N global different-URL loads, and normal authenticated PNG decode/cache/deduplication. Invalid payloads must never call decode.
- [ ] **Minimum correction:** Stream response bytes; reject status/type/declared size first and cumulative overflow immediately. Use a cancellation-safe global admission actor around transport, checked pixel multiplication via ImageIO before downsample, and configurable release limits while preserving token headers and sanitized cache keys.
- [ ] **GREEN:** Run all `ImageCacheTests`; measure Home artwork fill against baseline and require oversize failure to show the existing placeholder without blocking Home.
- [ ] **Mutation:** Remove cumulative byte enforcement, raise/bypass admission, then skip pixel bounds; chunked, concurrency, and pixel tests must fail. Restore and rerun GREEN.
- [ ] **Commit:** Stage the pipeline and test, `git diff --check`, commit `fix: bound artwork resource usage`.

### Task 10: Remove Swift concurrency lock warnings as distinct release hardening

**Files:** Modify `PlaybackEngine/Sources/PlaybackEngine/MediaGateway/CacheResourceLoaderDelegate.swift`; create `Tests/PlaybackEngineTests/CacheResourceLoaderDelegateConcurrencyTests.swift` or extend `PlaybackDropResilienceTests.swift` if its existing fixture can exercise the state directly.

- [ ] **RED:** Capture the build diagnostics naming `CacheResourceLoaderDelegate.swift:131,134` (`NSLock.lock/unlock` unavailable from async contexts) and add state tests for lowest-starved/furthest-active targeting during publish, completion, cancellation, and concurrent updates.
- [ ] **Minimum correction:** Move each dictionary mutation/target computation into one synchronous `mapLock.withLock` closure or a focused synchronous locked-state helper. Return the target, release the lock, then `await downloader.setPlayhead`; hold no lock across suspension and preserve task cancellation.
- [ ] **GREEN:** Run the new/extended tests plus `PlaybackDropResilienceTests` and `CacheLoaderLiveIntegrationTests`; rebuild iOS and tvOS and require an exact diagnostic scan for the two warnings to be empty. Do not change `SWIFT_VERSION` outside `project.yml` or hide warnings.
- [ ] **Mutation:** Restore `lock()`/`unlock()` inside async `publish`; the exact diagnostic gate must fail and state tests must still guard behavior. Restore and rerun GREEN.
- [ ] **Commit:** Stage only delegate and test, `git diff --check`, commit `fix: scope cache loader locking for Swift concurrency`.

### Task 11: Regenerate, document, and run the no-publication release gate

**Files:** Modify `PLANS.md` and `OPTIMIZATION_AUDIT.md`; regenerate `ReelFin.xcodeproj` only through `xcodegen generate`; no version/upload mutation in this task.

- [ ] **RED/gate definition:** Record acceptance rows for all nine findings, measured connection/HLS/image budgets, the concurrency warnings, and residual device/server unknowns. Any unreproduced relevant test, original bypass, new validated high/medium, secret artifact, or iOS/tvOS regression is a blocking RED.
- [ ] **Minimum correction:** Run `xcodegen generate`, review generated diff against `project.yml`, `git diff --check`, isolated uv ScriptTests, all focused security suites, full ReelFin iOS tests, ReelFinTV build/tests on 26.5, and the hardened non-destructive real Jellyfin E2E through ephemeral secret input. Do not alter users, libraries, collections, server settings, Apple state, or publication state.
- [ ] **GREEN/regressions:** Revalidate every original scan source-to-sink path plus alternate bypass, run a final security diff review, classify skips, and record exact commands/results. Require auth/Home P0 tests, launch, library, focus, Direct Play, native MKV/HLS, play/pause/seek/resume/stop, artwork, and log-cleanliness gates.
- [ ] **Mutation:** For final gate scripts/tests only, inject a nonsecret canary artifact and one known failing focused selector; prove the secret scanner and no-retry/failure propagation block the gate, then remove both and rerun GREEN.
- [ ] **Commit:** Stage only `PLANS.md`, `OPTIMIZATION_AUDIT.md`, and justified generated output; `git diff --check`; commit `docs: record Build 17 security validation`.
- [ ] **Handoff:** Only after this commit is green may the separate TestFlight workflow query existing builds and choose an unused build number. This plan itself never archives for upload, uploads, distributes, submits, or pushes.

## Final self-review checklist

- [ ] Findings map: Quick Connect; Range overflow; loopback/token/capacity; HLS bounds; Matroska bounds; URL allowlist; media/evidence privacy; QA password/uv; artwork budgets.
- [ ] Valid AVPlayer ranges are never silently capped; only internal streaming chunks are bounded.
- [ ] The connection default cites measured AVPlayer peak plus headroom, not an assumed number.
- [ ] Every operational Python entry, command, shebang, and executable mode is inside the uv boundary.
- [ ] P0 auth commits remain reachable; `project.yml` remains authoritative; iOS/tvOS destinations are 26.5.
- [ ] The concurrency warning hardening is a distinct commit after the nine findings.
- [ ] No step promises zero bugs or absolute security, and no step performs publication.
