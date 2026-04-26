# Matroska / MKV

Implemented:

- `EBMLReader`
- `EBMLElementID`
- `MatroskaSegmentParser`
- `MatroskaTrackParser`
- `MatroskaClusterParser`
- `MatroskaCueParser`
- `MatroskaSeekHeadParser`

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
- SeekHead entries for late-file Cues lookup
- Cues
- Cluster `Timecode`
- `SimpleBlock`
- `BlockGroup` with `Block` and `ReferenceBlock`

Packet extraction supports non-laced blocks plus Xiph, fixed-size, and EBML laced
blocks. Resume and interactive seek prefer parsed Cues, can load Cues through
SeekHead even when they sit outside the initial probe window, and fall back to a
bounded cluster scan only when no usable Cues exist.
