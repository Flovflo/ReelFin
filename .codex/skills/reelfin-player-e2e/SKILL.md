---
name: reelfin-player-e2e
description: Run ReelFin player validation for native Direct Play, Jellyfin live playback, iOS UI smoke tests, and tvOS build gates. Use when asked to verify ReelFin playback, Direct Play, resume/seek behavior, subtitles/audio tracks, HDR/Dolby Vision readiness, or to run the standard player QA suite.
---

# ReelFin Player E2E

Use this skill for repeatable ReelFin playback validation. Do not print Jellyfin passwords, API keys, or full signed playback URLs.

## Required Inputs

Use the local env file:

```bash
/Users/florian/Documents/Projet/ReelFin/.artifacts/secrets/reelfin-e2e.env
```

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

Values equal to `...` are placeholders and must fail the live suite.

## Standard Command

From `/Users/florian/Documents/Projet/ReelFin`:

```bash
scripts/run_reelfin_player_e2e.sh
```

Useful faster variants:

```bash
scripts/run_reelfin_player_e2e.sh --skip-ui --skip-tvos --loops 1 --sample-size 4
scripts/run_reelfin_player_e2e.sh --loops 3 --sample-size 10
```

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
