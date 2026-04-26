# HDR / Dolby Vision

Implemented:

- `HDRMetadata`
- `DolbyVisionMetadata`
- `ColorPrimaries`
- `TransferFunction`
- `MatrixCoefficients`
- `MasteringDisplayMetadata`
- `ContentLightLevelMetadata`
- `HDRPlaybackReport`

Current detection:

- Matroska Colour values map BT.2020, PQ, HLG, BT.709, BT.2020 matrix variants, bit depth, MaxCLL, MaxFALL, and mastering luminance where present.
- MP4 sample descriptions are inspected through CoreMedia format descriptions so `hvc1`/`hev1` HDR10, HLG, and Dolby Vision-coded entries can seed `HDRMetadata`.

Current preservation:

- Demuxed video tracks carry `HDRMetadata` on `MediaTrack`.
- HEVC compressed sample-buffer output creates `CMVideoFormatDescription` values with CoreMedia color-primary, transfer-function, YCbCr-matrix, and bit-depth extensions.
- Native MP4 sample-buffer playback preserves compressed samples instead of forcing 8-bit decoded pixel buffers.
- Apple Direct Play configures AVKit for HDR-capable presentation: iOS requests high dynamic range playback, and tvOS lets AVKit apply preferred display criteria automatically.
- tvOS native sample-buffer playback sets `AVDisplayCriteria` from the first video sample format description so the system can switch display mode when the sample metadata is sufficient.
- Diagnostics expose the detected HDR format and Dolby Vision profile so unknown/degraded paths remain visible.

Current limitations:

- Dolby Vision profile extraction is modeled but not fully parsed from codec private data.
- Dolby Vision dynamic metadata/RPU enhancement handling is not synthesized by the custom sample-buffer path; it depends on Apple accepting the tagged compressed HEVC stream.
- Final HDR/Dolby Vision output still needs validation on real HDR/Dolby Vision hardware. Simulator builds prove API correctness, not panel mode switching or tone mapping.
- Diagnostics must continue reporting degraded/unknown instead of claiming Dolby Vision playback when container metadata is incomplete.
