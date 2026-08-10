# HEVC HLS manifest compatibility design

## Context

Strict AVPlayer validation of the synthetic HLS path exposed two contradictions before the init segment was requested:

- a Main 10 HEVC source explicitly described as SDR was advertised as `VIDEO-RANGE=PQ` solely because it was 10-bit;
- every HEVC source was advertised as `hvc1.2.4.L153.B0`, regardless of the profile, compatibility, tier, level, and constraint bytes carried by its `hvcC` record.

The same local route and capability flow reached init and media segments for the H.264 fixture, so the rejected HEVC variant is a manifest compatibility defect, not a loopback authorization defect.

## Product contract

- `VIDEO-RANGE=PQ` is emitted only for explicit PQ evidence: transfer characteristic 16, Dolby Vision metadata, or an explicit HDR10/DOVI plan range.
- `VIDEO-RANGE=HLG` is emitted only for transfer characteristic 18.
- Main 10 alone never upgrades an SDR or unknown source to HDR.
- The HEVC `CODECS` parameter is derived from the source `HEVCDecoderConfigurationRecord` and its effective sample entry (`hvc1`/`hev1`), not from a constant.
- Malformed or truncated `hvcC` fails closed into an explicit unsupported/fallback decision; it must not produce a plausible but false codec string.
- Dolby Vision supplemental signaling and the now-correct H.264 `avc1` path remain unchanged.

## HEVC codec projection

Parse the 13-byte general profile/tier/level prefix of `hvcC` with checked bounds:

- profile space and profile id from byte 1;
- the 32 compatibility flags from bytes 2...5, projected with the bit order required by ISO/IEC 14496-15 Annex E;
- tier flag from byte 1;
- level idc from byte 12;
- constraint indicator bytes 6...11, dropping only trailing zero bytes.

The result is the fully qualified `hvc1.*` or `hev1.*` string used by the master playlist. Parsing and formatting live in one small value type so playlist tests and packaging decisions share one implementation.

## Validation

Use a real HEVC fixture and AVPlayer on iOS 26.5. Validate the two attributes independently before the combined GREEN:

1. an SDR Main 10 fixture must omit `VIDEO-RANGE` while retaining a codec string derived from its `hvcC`;
2. a PQ fixture must emit `VIDEO-RANGE=PQ`;
3. the SDR fixture must reach init and media requests, `readyToPlay`, time progression, seek, and replay;
4. H.264, HDR10, and Dolby Vision decision and manifest suites must remain green.

The local route classifier may record only route classes while diagnosing requests; it must not expose the capability value.

