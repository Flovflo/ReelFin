# Build 17 Security Hardening Design

## Status and boundary

This design turns the nine validated findings from security scan `dbde6617-f731-4a48-8d76-fa5212d6fc0b` into independently reviewable Build 17 work. It preserves the expired-session recovery commits already on `codex/reelfin-release-hardening` and does not authorize an upload, TestFlight distribution, App Store submission, GitHub push, Apple-account change, or Jellyfin mutation.

`project.yml` remains the only project configuration source. The generated Xcode project is regenerated, never hand-edited. Validation uses the Swift 6 compiler in Xcode with the repository's current language setting, iOS/tvOS 26.5 simulator destinations, and isolated uv-managed Python only.

## Security invariants

1. A Quick Connect capability is useful only at the normalized Jellyfin origin that issued it. A newer initiation or sign-out makes an older handshake inert.
2. Hostile HTTP ranges never trap or overflow. Valid AVPlayer ranges retain their complete HTTP meaning; large bodies are streamed in transparent internal chunks rather than silently shortened to a fixed ceiling.
3. Local playback listeners accept only IPv4 loopback traffic and only unguessable, session-scoped routes. A connection admission limit is selected from measured AVPlayer behavior, with documented headroom, rather than assumed.
4. Synthetic HLS serves only segments advertised by the current playlist and retains a measured, bounded working set. A far-future route cannot make the packager generate intervening media.
5. Every Matroska child range is checked against its parent and the available bytes before conversion, addition, slicing, or cursor advancement.
6. URL diagnostics are allowlist projections. They never fall back to raw URLs or reveal userinfo, path components, fragments, query values, or signed capabilities.
7. Normal and deep playback diagnostics use process-local correlation values, bounded protected storage, and structured allowlisted fields; they do not persist raw library identities or free-form server/media text.
8. Credentialed QA never passes passwords or signed URLs in files or command arguments, and never persists them in logs or result bundles. Every operational Python path, including direct execution paths and shebangs, is forced through the isolated uv wrapper.
9. Artwork transport enforces response type, encoded-byte, decoded-pixel, and concurrent-load budgets before expensive decode/cache work.
10. Release builds contain no known `NSLock.lock()`/`unlock()` calls from async contexts in `CacheResourceLoaderDelegate`; scoped synchronous critical sections preserve downloader targeting under the Swift 6 concurrency model.

## Component design

### Origin-bound Quick Connect

`JellyfinAPIClient` owns one pending handshake containing a monotonically increasing generation, normalized server base URL, and secret. Initiation does not replace persisted configuration. Poll and exchange read the origin from the matching pending handshake and recheck generation after every suspension. Configuration, session, and token persistence change together only after successful exchange; secrets never enter logs or event payloads.

### Checked, complete HTTP ranges

Parsing retains semantic `start`, optional inclusive `end`, or suffix length without first converting attacker-controlled arithmetic into `ByteRange`. Resolution occurs only after the real resource length is known. It validates representability and uses overflow-reporting arithmetic to construct a half-open `Int64` interval inside the resource.

The resolved interval is the interval advertised in `Content-Range` and `Content-Length`, and the server streams that entire interval. Existing 4 MiB reads and 1 MiB socket writes remain internal implementation chunks. No 16 MiB or other fixed ceiling may alter the externally visible range or truncate an otherwise valid AVPlayer request.

### Loopback capability and measured admission

Both local servers use a shared factory that binds `NWListener` to `127.0.0.1` and a shared 256-bit random path capability. Exact path-segment comparison happens before cache, downloader, demuxer, or repackager work. Capability rotation occurs per server/playback session, and logs receive only route classes.

Connection admission is a denial-of-service boundary, but an undersized limit is also a playback defect. Instrumented tests and the real player gate record peak simultaneous connections for startup, metadata probing, seek, reread, and HLS refresh. The checked-in release capacity is then chosen above that observed peak with explicit headroom and is tested both for legitimate bursts and deterministic refusal above the limit. Accepted connections remain tracked and canceled at stop/deinit.

### Bounded synthetic HLS

The HTTP layer accepts only anchored nonnegative segment routes and asks the session only for an advertised sequence. Generation is sequential and owned by bounded prefetch, not by arbitrary HTTP input. Playlist advertisement, duration metadata, and encoded fragment storage form one sliding working set with a byte budget and a measured segment window. Seek resets the relevant generation/advertisement state. Rereads of still-advertised segments remain cache hits.

### Checked EBML tree

`EBMLReader` becomes the single range authority. Its checked helper validates integer conversion, checked endpoint addition, containment within the current parent, containment within `data.count`, and forward cursor progress. Nested unknown-size elements are rejected; only a top-level Segment may use an explicitly supplied enclosing end. All Matroska parsers remove local `payloadEnd` arithmetic and direct unvalidated slices.

### Privacy-safe diagnostics and runners

URL logs share one allowlist projection: normalized origin, a short one-process or one-build correlation for the path, allowlisted parameter names, and counts only. Media identities use a random process-local HMAC correlation when correlation is necessary; normal logs otherwise retain only operational categories and numeric playback facts.

Deep evidence is opt-in, structured, stored under protected Caches, owner-only, and rotated to a fixed total budget. It rejects caller-provided free text. QA evidence is updated to correlate by random session and route facts instead of raw item IDs.

The repository has one Python execution boundary, `scripts/run_python_with_uv.sh`, pinned to the isolated uv installation and a managed Python version. Active shell commands call only that wrapper. Python files that could be directly executed do not retain an operational system-Python shebang or executable bit. Credentialed runners accept secret input only through stdin or an already-populated ephemeral environment variable, redact stdout/stderr before persistence, omit credentialed `.xcresult` bundles, and scan retained text artifacts without printing the matching value.

### Bounded artwork

The image pipeline checks status and `image/*` type, rejects declared oversize content before body accumulation, and rejects chunked/incorrectly declared bodies as soon as cumulative bytes cross the limit. It validates pixel multiplication before decode/downsample and uses a cancellation-safe global network admission gate while retaining per-URL request deduplication. Limits are injectable for deterministic tests; release values are documented and measured against Home fill behavior.

### Swift concurrency warning hardening

`CacheResourceLoaderDelegate` keeps its short synchronous dictionary critical sections but expresses them through `NSLock.withLock` (or a focused synchronous state helper). No lock is held across an `await`. Tests cover target selection while requests are published, starved, completed, and canceled. This is a separate hardening commit after the nine findings so it cannot obscure their diffs.

## Validation and release decision

Every remediation follows RED, minimal correction, GREEN, deliberate mutation failure, restored GREEN, focused regression suite, and one scoped commit. The final gate regenerates from `project.yml`, runs `git diff --check`, all uv ScriptTests, focused security suites, full iOS tests, tvOS build/tests, and non-destructive real Jellyfin player validation when the ephemeral credentials and fixtures are available. It also rereads every original source-to-sink path and performs a final security diff review.

Build 17 remains blocked if an original exploit still reproduces, a legitimate playback control regresses, a relevant test cannot run, a new high/medium finding is validated, the concurrency warnings remain, or secret-artifact checks fail. Passing these gates is rigorous evidence for the tested scope, not a claim of zero defects or absolute security.

## Compatibility and residual risks

- Loopback binding and AVPlayer connection behavior still require physical-device evidence before claiming identical hardware behavior.
- Sliding HLS retention can affect late rereads and backward seeks; both are explicit release blockers.
- Rejecting nested unknown-size Matroska elements may exclude unusual legal files and must be documented with real MKV/WebM controls.
- Image budgets may reject exceptionally large custom artwork; the UI must fall back without blocking Home.
- Sanitized diagnostics deliberately reduce forensic detail.
- Simulator and non-destructive server tests do not prove HDMI, HDR/Dolby Vision rendering, every codec/container, or every server topology.
