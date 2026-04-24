# Performance

Implemented foundations:

- Bounded media cache window.
- Range request metrics.
- Read throughput metrics.
- Retry count and network stall fields.
- Clock/sync diagnostics.
- Decode/render diagnostic structs.

Not yet measured:

- Startup time to first decoded frame.
- Seek latency.
- CPU/GPU averages.
- Memory peak.
- Real dropped-frame behavior.

The current branch proves the instrumentation surfaces, not final performance.
