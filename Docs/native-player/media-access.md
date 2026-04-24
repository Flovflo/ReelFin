# Media Access

Implemented in `NativeMediaCore/MediaAccess`:

- `MediaByteSource`
- `HTTPRangeByteSource`
- `BufferedByteReader`
- `ReadAheadController`
- `MediaCacheWindow`
- `NetworkBackpressureController`

`HTTPRangeByteSource` performs byte-range `GET` requests, retries transient failures, records range count, throughput, retry count, current offset, and buffered ranges. It does not download whole files into memory.

Current gaps:

- No disk cache.
- No adaptive read-ahead policy wired to demuxer demand yet.
- Backpressure is a policy helper, not globally enforced.
