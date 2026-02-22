# Playback QA Protocol

## 1) Automated loop (CLI)

Run the unit/integration loop repeatedly on the simulator:

```bash
./scripts/run_playback_qa_loop.sh 5
```

- Argument 1: number of loops.
- Argument 2 (optional): simulator device ID.
- Includes:
  - `PlaybackEngineTests`
  - `ImageCacheTests`
  - optional live-server playback probes
  - app install + launch on simulator

Enable live playback probes (real Jellyfin server) by exporting env vars:

```bash
export REELFIN_TEST_SERVER_URL="https://your-server.example.com"
export REELFIN_TEST_USERNAME="your-user"
export REELFIN_TEST_PASSWORD="your-password"
export REELFIN_TEST_LOOPS=2
export REELFIN_TEST_SAMPLE_SIZE=8
export REELFIN_TEST_MAX_FAILURES=0
./scripts/run_playback_qa_loop.sh 5
```

`PlaybackIntegrationProbeTests` will authenticate, fetch home items, resolve playback URLs, and probe manifest + segment reachability in loop.

## 2) Real-server playback probe loop (in-app)

From **Settings**:

1. Open **Playback Diagnostics**.
2. Set:
   - `Loops`
   - `Items`
3. Tap **Run Playback Diagnostics Loop**.

The diagnostics loop automatically:
- fetches home feed items,
- resolves playback URLs for each item,
- probes master manifest and first segment accessibility,
- tries `serverDefault` and `conservativeCompatibility` transcode profiles,
- generates a pass/fail report.

Use this report for quick triage when users report black-screen/startup failures.
