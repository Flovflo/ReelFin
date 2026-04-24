# Subtitles

Implemented:

- `SubtitleParser`
- `SubtitleCue`
- `SubtitleStyle`
- `SRTParser`
- `WebVTTParser`
- `ASSParser`
- `PGSSubtitlePacket`
- `VobSubPacket`

Supported now:

- External SRT parsing.
- External WebVTT parsing.
- ASS style/event parsing with unsupported animated override reporting.

Planned/incomplete:

- Subtitle overlay timing is represented but not fully wired to playback clock.
- Matroska embedded text subtitle extraction depends on packet delivery.
- PGS/VobSub packet models exist; image decode/render is not implemented.
