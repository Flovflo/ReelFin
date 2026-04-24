# Licensing / Security

No VLC, libVLC, FFmpeg, or GPL code was added.

Dependencies added: none.

Security behavior:

- Original media URLs are redacted before diagnostic string output.
- `api_key` is supported for Apple helper compatibility but must not be logged raw.
- `HTTPRangeByteSource` supports auth headers and range reads without whole-file buffering.
- Subtitle parsers treat subtitle files as untrusted text; ASS support parses styles/events and strips override blocks from rendered text.

Risks:

- Future software codec backends may carry license, patent, App Store, and binary-size implications.
- Native libraries must stay behind Swift protocols and require explicit licensing review before integration.
