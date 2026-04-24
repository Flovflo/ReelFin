# Demuxing

Implemented protocols:

- `MediaDemuxer`
- `DemuxerFactory`
- `MediaPacket`
- `MediaTrack`
- `PacketReader`
- `SeekIndex`
- `TimestampMapper`
- `SeekMap`

Backends:

- `MP4Demuxer`: AVFoundation helper for MP4/MOV track enumeration.
- `MatroskaDemuxer`: custom EBML parser for Matroska/WebM metadata and basic packets.

Important limitation: `MP4Demuxer.readNextPacket()` is not implemented yet. Matroska `SimpleBlock` packet extraction exists for non-laced blocks; laced packets fail with an explicit Matroska error.
