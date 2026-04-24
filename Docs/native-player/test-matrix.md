# Test Matrix

| Category | Current expected result |
| --- | --- |
| MP4 H.264 AAC SDR | Container/track enumeration via AVFoundation helper; full packet decode/render incomplete. |
| MP4 HEVC AAC SDR | Container/track enumeration; HEVC VideoToolbox setup stops at explicit hvcC parser gap. |
| MP4 HEVC HDR10 | HDR architecture exists; preservation not proven. |
| MP4 Dolby Vision | DV metadata modeled; profile parsing/preservation not proven. |
| MKV H.264 AC-3 | EBML/tracks/basic packets parse; H.264 routes to VideoToolbox plan; AC-3 routes to Apple audio plan. |
| MKV HEVC E-AC-3 | EBML/tracks parse; HEVC routes to VideoToolbox but hvcC parser incomplete. |
| MKV HEVC TrueHD Atmos | TrueHD reported as experimental software backend, not decoded. |
| MKV HEVC DTS-HD MA | DTS reported as experimental software backend, not decoded. |
| MKV AV1 Opus | AV1/Opus backend strategy visible; decode incomplete. |
| MKV VP9 Opus | VP9 reports missing software backend. |
| Anime MKV ASS | ASS parser foundation works; embedded timing/render wiring incomplete. |
| Blu-ray remux PGS | PGS packet model exists; image decode/render incomplete. |
| VobSub subtitles | Packet model exists; image decode/render incomplete. |
| High bitrate 4K HDR remux | Range/probe/metadata path can inspect; performance not proven. |

Automated tests cover config defaults, original URL resolution, range reads, probes, Matroska parsing, planner decisions, diagnostics, subtitles, and HDR mapping.
