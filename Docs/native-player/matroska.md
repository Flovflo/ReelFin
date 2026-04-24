# Matroska / MKV

Implemented:

- `EBMLReader`
- `EBMLElementID`
- `MatroskaSegmentParser`
- `MatroskaTrackParser`
- `MatroskaClusterParser`
- `MatroskaCueParser`
- `MatroskaSeekHeadParser` placeholder

Parsed elements:

- EBML header
- Segment
- Info: `TimecodeScale`, `Duration`
- Tracks / TrackEntry
- Track number/type
- CodecID / CodecPrivate
- Language / Name
- Default and forced flags
- DefaultDuration
- Video width/height and Colour HDR metadata
- Audio channels/sample rate/bit depth
- Cues
- Cluster `Timecode`
- `SimpleBlock`
- `BlockGroup` with `Block` and `ReferenceBlock`

Packet extraction supports non-laced blocks only. Xiph/fixed/EBML lacing is intentionally not hidden; it reports an explicit incomplete packet extraction reason.
