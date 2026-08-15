# Task 2 report — hostile HTTP ranges

## Outcome

Fixed. A client-controlled `Range` header reached `LocalMediaGatewayHTTPRequest.range(fromHeaderLine:)`, where `end - start + 1` trapped for `bytes=0-9223372036854775807`. Malformed Range headers were also silently converted to `range == nil`, and the cache proxy constructed endpoints and headers with unchecked arithmetic.

The enforced invariant is now: parse semantic nonnegative Int64 bounds, distinguish malformed Range from an absent Range, resolve a checked non-empty half-open interval only after the resource length is known, require that interval to be inside the resource, derive response headers from the resolved interval, and stream that complete interval without a 16 MiB clamp.

## RED

- `testMultiRangeRequestIsRejectedInsteadOfBeingTreatedAsNoRange`: exit 65; request parsed successfully with `range: nil` instead of being rejected.
- `testClosedRangeEndingAtInt64MaxIsRejectedWithoutOverflow`: exit 65; XCTest reported an unexpected exit/crash and restarted, proving the inclusive-length trap.
- Independent review added `testClosedEndOutsideResourceIsRejectedByOriginGateway`: the origin gateway returned 206 with `Content-Range: bytes 0-31/32` for `bytes=0-32`, proving its legacy session path still clamped an invalid closed range.
- Review round 1 added `testColdCacheProxyRejectsInt64MaxOpenRangeWithoutOverflow`: on an empty cache with unknown size, `bytes=9223372036854775807-` reached the first on-demand origin request and caused an unexpected XCTest exit/crash in `from + length - 1` instead of returning 416.
- Review round 1 added `testSuffixLargerThanImplicitWindowStreamsCompleteTail`: `bytes=-4195329` returned only 4,194,304 bytes with `Content-Range: bytes 2049-4196352/4196353`, proving the origin path still capped suffixes at the implicit 4 MiB window.
- Review round 2 added `testColdCacheProxyDoesNotMapIgnoredRangeBodyToNonzeroOffset`: a cold proxy requested `bytes=4-7` from a localhost origin that ignored Range and returned 200; the proxy stored the body beginning `[0,1,2,3,…]` at offset 4 and then served `[0,1,2,3]` under `Content-Range: bytes 4-7/64`.
- Review round 3 expanded that ignored-Range regression to a streaming 12 MiB origin and added `testColdCacheProxyBoundsOversized206ToInternalFetchWindow`. With `URLSession.data(for:)`, the ignored-Range path consumed 25,165,824 bytes across its rejected nonzero request and zero fallback, then cached all 12 MiB; the oversized 206 consumed 12,582,908 bytes and cached through offset 12,582,912. Both violated the 4 MiB internal fetch window.
- The new class also encodes open-ended Int64.max, `bytes=-0`, endpoints outside a 32-byte resource, valid `0-0`, `4-7`, `4-`, suffix, and a 16 MiB + 1,025-byte control.

## Correction

- `LocalMediaGatewayHTTP.swift`
  - rejects duplicate, malformed, suffix-zero, and multi-range headers instead of treating them as no Range;
  - stores bounded requests as semantic Int64 start/end values, without constructing `ByteRange` during parsing;
  - resolves requests to a checked Int64 half-open interval after the total length is known;
  - uses `subtractingReportingOverflow` and `addingReportingOverflow` for compatibility widths and endpoints;
  - derives `Content-Length` and `Content-Range` from the checked resolved interval.
- `LocalCacheHTTPServer.swift`
  - replaces unchecked/clamping tuple arithmetic with the centralized resolved interval;
  - passes the full interval to the existing 4 MiB cache/origin reads and 1 MiB socket slices;
  - forms every internal origin endpoint with reporting-overflow checks and uses a safe offset-zero size-discovery probe when an unresolved requested offset cannot form a valid probe interval;
  - accepts an origin 200 only for offset zero; a failed nonzero probe retries safely from zero, so an origin that ignores Range cannot poison a nonzero cache interval.
  - replaces the whole-body `data(for:)` on-demand read with the existing delegate-driven bulk `HTTPChunkedRangeReader`, capped to the current 4 MiB `serveChunk` request;
  - validates status and `Content-Range` in the response callback before accepting payload bytes: 200 is accepted only at offset zero, 206 must start at the requested offset and must either cover the internal window or end exactly at the checked resource EOF;
  - cancels a rejected response at headers and cancels an accepted oversized response as soon as the internal window is full. This does not clamp the client-visible interval: the outer cache server continues serving it through successive internal chunks.
- `HTTPChunkedRangeReader.swift`
  - adds an optional sendable response validator executed by `URLSessionDataDelegate` before `.allow`;
  - adds a shared-session overload that installs the bounded reader as the individual data task's delegate, retaining `MediaOriginTransport.onDemand` connection pooling and process-wide transport learning;
  - preserves bulk `Data` delegate callbacks and task cancellation. No `URLSession.AsyncBytes`, byte-at-a-time loop, Swift language migration, or new AsyncBytes/performance warning was introduced.
- `LocalMediaGatewaySession.swift`
  - removes the origin gateway's legacy closed-range clamp;
  - resolves bounded ranges against the actual resource length before streaming, so an endpoint outside the resource is consistently rejected with 416;
  - resolves suffixes against the real length and routes suffixes larger than 4 MiB through the existing bounded, cancelable chunk stream without altering their interval.

## GREEN evidence

- `LocalMediaGatewayHTTPRangeSecurityTests`: 9/9 passed, including the origin-session bypass and complete large-suffix regressions.
- `LocalMediaGatewayServerTests`: 31 executed, 3 live-environment skips, 0 failures.
- `PlaybackDropResilienceTests`: 28/28 passed in 381.657 seconds.
  - Includes open-ended cache proxy, keep-alive/replay, origin reset, and byte-exact cache proxy delivery of 19,117,337 bytes (>16 MiB).
- Post-correction verification: the complete new class plus all `LocalMediaGatewayServerTests` executed 39 tests, with 3 live-environment skips and 0 failures. An earlier post-mutation combined run also passed the 7-test class, all server tests, and `testCacheProxyServesExactBytesThroughReset` with the same 39/3/0 result.
- Review round 1 final selection: 43 tests executed, 3 live-environment skips, 0 failures in 118.923 seconds. This comprised the 9-test security class, all 31 server tests, and three cache-path controls: hostile cold-cache Range, open-ended size adoption, and byte-exact reset delivery of 19,117,337 bytes.
- Review round 2 final selection: 45 tests executed, 3 live-environment skips, 0 failures in 136.428 seconds. This comprised the 9-test security class, all 31 server tests, and five cache controls: ignored Range, hostile Int64.max, open-ended size adoption, deep resume (52.09 seconds reached, 0 stalls, 3.94-second first frame), and exact reset delivery of 19,117,337 bytes.
- Review round 3 isolated GREEN: ignored 200 and oversized 206 regressions passed 2/2 in 0.448 seconds; after admitting a legitimate short-at-EOF 206, the two new regressions plus the hostile Int64.max cold-cache control passed 3/3 in 0.449 seconds.
- Review round 3 post-fix security/gateway selection: 40 tests executed, 3 live-environment skips, 0 failures in 18.861 seconds (9 security + 31 gateway).
- The final shared-session delegate variant passed hostile/ignored/oversized plus the localhost sequential keep-alive control: 4/4, 0 failures. The keep-alive fixture spent 79 seconds generating its media asset before completing; the three bounded-range cases themselves completed in 0.465 seconds.
- Review round 3 cache evidence from the targeted combined run: reset/no-refetch passed in 114.180 seconds; open-ended adoption passed; deep resume reached 52.08 seconds with 0 stalls and a 3.84-second first frame; byte-exact reset delivered all 19,117,337 bytes; both new bounded-origin regressions and localhost keep-alive passed. That run exposed the now-fixed valid-EOF rejection in the hostile Int64.max test; the final isolated rerun passed it in 0.010 seconds.

## Mutation evidence

1. Restored `end - start + 1`: overflow test caused an unexpected XCTest exit/crash and failed. Restored checked arithmetic.
2. Removed the resource-bound guard: `bytes=32-32` resolved to `[32, 33)` for a 32-byte resource and the out-of-resource test failed. Restored the guard.
3. Introduced a visible 16 MiB clamp: the large-range test observed endExclusive 16,777,216 instead of 16,778,241 and failed. Removed the clamp.
4. Restored unchecked `from + Int64(length) - 1` in the cold-cache origin probe: the hostile proxy test again caused an unexpected XCTest exit/crash. Restored reporting-overflow checks and the safe discovery probe.
5. Reintroduced the 4 MiB suffix cap in the streaming branch: the suffix test received 4,194,304 instead of 4,195,329 bytes and the headers exposed the shortened interval. Restored the complete resolved suffix.
6. Reaccepted origin 200 responses for a nonzero `from`: the ignored-Range regression again received `[0,1,2,3]` under the advertised 4-7 interval. Restored the `from == 0` requirement and safe zero-offset retry.
7. Replaced the bounded reader's `maxLength: length` with `Int.max`: the ignored-Range test consumed 12,648,448 bytes and cached 12 MiB; the oversized-206 test consumed 12,582,908 bytes and cached the full oversized interval. Both tests failed their network and cache-bound assertions. Restored `maxLength: length`; the isolated pair returned GREEN.

## Commands

```text
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/LocalMediaGatewayHTTPRangeSecurityTests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/LocalMediaGatewayServerTests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/LocalMediaGatewayHTTPRangeSecurityTests -only-testing:PlaybackEngineTests/LocalMediaGatewayServerTests -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testCacheProxyServesExactBytesThroughReset
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/LocalMediaGatewayHTTPRangeSecurityTests -only-testing:PlaybackEngineTests/LocalMediaGatewayServerTests -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyRejectsInt64MaxOpenRangeWithoutOverflow -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testCacheProxyBoundsOpenEndedRangeAndAdoptsContentInfo -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testCacheProxyServesExactBytesThroughReset
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:PlaybackEngineTests/LocalMediaGatewayHTTPRangeSecurityTests -only-testing:PlaybackEngineTests/LocalMediaGatewayServerTests -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyDoesNotMapIgnoredRangeBodyToNonzeroOffset -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyRejectsInt64MaxOpenRangeWithoutOverflow -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testCacheProxyBoundsOpenEndedRangeAndAdoptsContentInfo -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testCacheProxyDeepResumeFastStartOnDemand -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testCacheProxyServesExactBytesThroughReset
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,id=9CF14BF1-92B4-4BD9-B231-B273A5B27897' -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyDoesNotMapIgnoredRangeBodyToNonzeroOffset -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyBoundsOversized206ToInternalFetchWindow
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,id=9CF14BF1-92B4-4BD9-B231-B273A5B27897' -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyRejectsInt64MaxOpenRangeWithoutOverflow -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyDoesNotMapIgnoredRangeBodyToNonzeroOffset -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyBoundsOversized206ToInternalFetchWindow
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,id=9CF14BF1-92B4-4BD9-B231-B273A5B27897' -only-testing:PlaybackEngineTests/LocalMediaGatewayHTTPRangeSecurityTests -only-testing:PlaybackEngineTests/LocalMediaGatewayServerTests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin -destination 'platform=iOS Simulator,id=9CF14BF1-92B4-4BD9-B231-B273A5B27897' -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyRejectsInt64MaxOpenRangeWithoutOverflow -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyDoesNotMapIgnoredRangeBodyToNonzeroOffset -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testColdCacheProxyBoundsOversized206ToInternalFetchWindow -only-testing:PlaybackEngineTests/PlaybackDropResilienceTests/testServerReusesOneConnectionAcrossSequentialRanges
git diff --check
```

## Auto-review

- Scope includes the two requested production files plus `LocalMediaGatewaySession.swift`, where review found origin-path semantic clamps. It also includes one generated pbxproj inclusion, the security regression class, and one cache-path regression in `PlaybackDropResilienceTests`. XcodeGen's unrelated scheme rewrites were restored mechanically.
- The parser no longer has a path from hostile bounds to `ByteRange` construction.
- The cache proxy streams `resolvedRange.start ..< resolvedRange.endExclusive` unchanged; there is no 16 MiB response clamp.
- Existing live Jellyfin tests were skipped because their opt-in environment was absent; tests used only in-process localhost origins. No external server, credential, secret, publication, archive, or external mutation was used.
- Review round 3 keeps client-visible Range semantics unchanged, bounds only the internal cache-miss transfer, validates headers before body delivery, and preserves cancellation, localhost HTTP keep-alive, and the process-shared origin connection pool. The localhost test origin may finish a few already-in-flight 32 KiB writes after header cancellation; it remains bounded to four transport chunks beyond the accepted 4 MiB fallback window rather than transmitting the 12 MiB body.
- Build output still contains pre-existing Swift concurrency warnings in `LocalCacheHTTPServer` and `CustomPlaybackEngine`; they are outside Task 2 and are addressed by later plan tasks.
