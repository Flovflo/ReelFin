# Task 11 Report — Build 17 no-publication release gate

Date: 2026-08-12

Final reviewed source: `73eef4976d909c4a6453587879e314b9e100401c`

## Outcome

The release code gate is PASS. The complete matrix ran on `cd2cb32`; the sole subsequent delta is a test-only iPad accessibility correction in `IPadAdaptiveUITests.swift`. A fresh proportional iPad rerun on `73eef49` passed all three selected UI tests. An independent rereviewer repeated the 3/3 result, found no issue, and passed `git diff --check`. No production source changed after the complete full-suite gate, so the 1,269-test iPhone unit run was not repeated.

This is a no-publication result. No archive, upload, distribution, App Review submission, Apple-state mutation, or push was performed.

## Evidence ledger

| Gate | Exact result | Classification |
| --- | --- | --- |
| HEAD/worktree | `73eef4976d909c4a6453587879e314b9e100401c`; clean before documentation | PASS |
| ScriptTests | `scripts/run_python_with_uv.sh -m unittest discover -s Tests/ScriptTests -p 'test_*.py'`: 55/55 | PASS |
| TestFlight preflight | Four screenshots per family; dimensions/alpha; SHA manifest; four public URLs | PASS |
| Deterministic gateway | `LocalMediaGatewayServerTests/testGatewayURLExposesPlayableMetadataForGeneratedMP4`: 1/1 | PASS |
| Focused A | PlaybackEngine selection 117 passed with six additional live skips; ImageCache 27/27; Quick Connect 16/16; 160 non-skipped passes, zero failures | PASS with classified skips |
| Focused B | Local/Synthetic HLS, manifests/timeline, native configuration/routing/controller: 129/129 | PASS |
| Publication policy | `PlayheadPublicationPolicyTests`: 8/8 | PASS |
| Full iPhone unit gate | PlaybackEngine 1,177 with ten skips; ImageCache 27; JellyfinAPI 65; total 1,269 executed, zero failures | PASS with classified skips |
| iPad proportional gate | Xcode-beta, `ReelFin`, iPad Pro 13-inch (M5), iOS 26.5; `IPadAdaptiveUITests` plus `AppStoreScreenshotTests/testCaptureScreenshots`: 3/3 | PASS |
| tvOS | `ReelFinTV` Apple TV 4K (3rd generation), tvOS 26.5: 18/18 tests, then distinct build | PASS |
| Storefront reviewer | Six UI invocations; 12/12 run-pairs strict zero-pixel delta; SHA promotion; all 12 raw images inspected | PASS |
| Static/runtime scans | Python boundary, shell syntax, Matroska bypass, raw cache-loader locks, scoped lock warnings, fatal runtime signatures, whitespace | PASS |

## Classified skips and residual evidence gaps

The ten full-suite skips are three credentialed cache-loader integrations, three live local-gateway/server scenarios, two live native-bridge URL cases, one native-bridge fixture-path case, and one live playback-integration probe. They are inputs absent from the offline gate, not silently converted successes.

The hardened Jellyfin E2E was not run: all seven required ephemeral inputs (`JELLYFIN_BASE_URL`, username, password, and four explicit media selectors) were absent. Simulator results do not prove physical HDR/Dolby Vision display or arbitrary remote server, artwork, codec, and network topologies.

## Security findings and measured bounds

All nine findings retain acceptance evidence: Quick Connect origin; checked HTTP Range arithmetic; loopback capability, admission, and lifecycle; bounded independent HLS; checked Matroska/EBML; allowlisted URL diagnostics; opaque bounded evidence; uv-only secret-safe runners; and bounded artwork resources.

- Local playback capacity: 24, derived from a measured progressive AVPlayer peak of 12. Strict HLS AVPlayer peaked at one; supplemental fan-out peaked at six.
- Synthetic HLS boundary search: 4,096 reads, 64 MiB, or 12 seconds; working-set default 12 segments.
- Artwork: 12 MiB encoded, 40 MP, four concurrent loads. The 34-file checked-in corpus maxima were 7,473,677 bytes and 6,681,600 pixels.
- Deep evidence: exact 1 MiB ceiling. Native handoff: 180-second lifetime and 64-entry bound.

These are measured policies with stated headroom, not universal safety or performance claims.

## Warning debt

Focused/full logs and the exact cache-loader diagnostic scan were clean. Cold compilation still reports Swift 6-forward actor-isolation warnings in `SampleBufferDisplayLayerRenderer` and `CustomPlaybackEngine` audio-interruption callbacks, plus deprecated AVFoundation sample-buffer APIs. The source of truth remains `SWIFT_VERSION: 5.9`; the warnings are non-blocking for this build and explicitly block a future Swift 6 migration until corrected.

## External release blockers

- Xcode 26.6 first-launch status exits 69 and needs human setup.
- All three App Review demo values are absent; credentials must never be invented.
- The historical App Review password requires rotation.
- DSA remains a human/legal decision.
- App Privacy is already published as Data Not Collected.
- `asc doctor` reports the ReelFin Admin keychain profile and private key healthy with no issues.

These conditions block release operations or live evidence, but they do not turn the validated source code gate RED.
