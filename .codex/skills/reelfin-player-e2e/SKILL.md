---
name: reelfin-player-e2e
description: Run ReelFin player validation for native Direct Play, Jellyfin live playback, iOS UI smoke tests, and tvOS build gates. Use when asked to verify ReelFin playback, Direct Play, resume/seek behavior, subtitles/audio tracks, HDR/Dolby Vision readiness, or to run the standard player QA suite.
---

# ReelFin Player E2E

Use this skill for repeatable ReelFin playback validation. Do not print Jellyfin passwords, API keys, or full signed playback URLs.

## Required Inputs

For live runs, provide the server and username through the runner's pre-existing ephemeral process environment. Provide the password through that same ephemeral environment or with `--password-stdin`. The runner captures these values into non-exported shell locals and immediately unsets inherited aliases. Do not pass passwords, API keys, signed URLs, or media item IDs as command-line arguments or put credentials in env files or QA artifact files.

Required keys:

```bash
JELLYFIN_BASE_URL
JELLYFIN_USERNAME
JELLYFIN_PASSWORD
TEST_DIRECTPLAY_MP4_ITEM_ID
TEST_MKV_ITEM_ID
TEST_HDR_ITEM_ID
TEST_DOLBY_VISION_ITEM_ID
```

Values equal to `...` are placeholders and must fail the live suite. A file passed with `--env-file` is optional and nonsecret; it accepts only the four `TEST_*_ITEM_ID` selectors and rejects credential-like keys.

## Standard Command

From the ReelFin repository root:

```bash
scripts/run_reelfin_player_e2e.sh
printf '%s\n' "${REELFIN_E2E_PASSWORD:?}" | scripts/run_reelfin_player_e2e.sh --password-stdin
```

Useful faster variants:

```bash
scripts/run_reelfin_player_e2e.sh --skip-ui --skip-tvos --loops 1 --sample-size 4
scripts/run_reelfin_player_e2e.sh --loops 3 --sample-size 10
```

The runner uses the fixed offline uv-managed Python 3.13 boundary. Credentialed DerivedData, simulator control state, resume state, and implicit XCTest results live only in an owner-only `mktemp` directory removed by one immutable exit/signal trap. Only redacted logs survive under `.artifacts/player-e2e/`; the runner scans them for exact and arbitrary upper/lower/mixed percent-encoded credential or item-selector values before reporting success. It never retains credentialed `.xcresult` bundles.

## Validation Gates

The runner must:

1. Regenerate the Xcode project with `xcodegen generate`.
2. Probe explicit Jellyfin item IDs with `scripts/live_directplay_item_probe.py`.
3. Verify Jellyfin resume reporting with `scripts/live_resume_reporting_probe.py`.
4. Benchmark explicit original streams with `scripts/live_player_benchmark.py`.
5. Run `scripts/live_playback_probe.py` against the live server.
6. Run deterministic iOS playback tests through the `ReelFin` scheme.
7. Run live iOS UI smoke unless `--skip-ui` is explicit.
8. Run the tvOS simulator build gate unless `--skip-tvos` is explicit.
9. Scan runner logs for fatal playback signatures such as VRP/CAPTION render
   pipeline failures, Main Thread Checker violations, and background
   CoreAnimation transactions.

## Evidence To Report

Report:

- artifact directory under `.artifacts/player-e2e/`
- pass/fail counts from explicit item probes
- live resume reporting result and restored item state warning if any
- original-stream benchmark p50/p95 range timings
- live probe summary
- xcodebuild result for deterministic tests
- iOS UI smoke result or explicit skip reason
- tvOS build result or explicit skip reason
- runtime log cleanliness result

Never claim HDR/Dolby Vision display proof from simulator-only evidence. Simulator validates route, metadata, and app behavior; real HDR/DV display still needs TestFlight on compatible Apple hardware.
