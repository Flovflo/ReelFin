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

Current limitations:

- Dolby Vision profile extraction is modeled but not fully parsed from codec private data.
- HDR preservation through the renderer is not proven yet.
- Diagnostics must report degraded/unknown instead of claiming Dolby Vision playback.
