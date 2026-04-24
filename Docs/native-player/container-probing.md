# Container Probing

`ContainerProbeService` probes original bytes first and uses metadata hints only when signatures are unknown.

Detected today:

- MP4/MOV via BMFF `ftyp`
- Matroska/MKV/WebM via EBML header plus hint/profile
- MPEG-TS via sync byte
- M2TS/program stream signature
- AVI via RIFF AVI
- FLV via `FLV`
- OGG via `OggS`

The probe result includes format, confidence, byte signature, MIME when provided, and reason.
