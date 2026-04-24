# Audio Pipeline

Implemented:

- `AudioDecoder`
- `AudioDecoderFactory`
- `AppleAudioDecoder`
- `SoftwareAudioDecoder`
- `DecodedAudioFrame`
- `AudioFormatDescriptor`
- `ChannelLayoutMapper`
- `AudioRenderer`
- `AVAudioEngineRenderer`
- `AudioClock`
- `MasterClock`
- `VideoClock`
- `ClockSynchronizer`
- `DriftCorrector`

Current status:

- AAC/MP3/ALAC/AC-3/E-AC-3/FLAC/PCM plan to Apple decode backends.
- TrueHD/DTS route to explicit software-module plans when experimental flags are enabled.
- PCM decode/render is not complete; `AVAudioEngineRenderer` is a rendering scaffold.
