# Video Pipeline

Implemented:

- `VideoDecoder`
- `VideoDecoderFactory`
- `VideoToolboxDecoder`
- `SoftwareVideoDecoder`
- `DecodedVideoFrame`
- `VideoCodecPrivateDataParser`
- `VideoRenderer`
- `SampleBufferDisplayLayerRenderer`
- `MetalVideoRenderer`
- `VideoFrameScheduler`
- `ColorSpaceMapper`
- `HDRRenderMetadata`

Current decode support:

- H.264 `avcC` parsing and VideoToolbox format description creation are implemented.
- HEVC routes to VideoToolbox but fails at the explicit `hvcC parser not complete` point.
- AV1/VP9/MPEG-2/VC-1 require software backends that are not implemented.

Current render support:

- Renderer protocols and diagnostics exist.
- SampleBuffer and Metal renderers are scaffolded, but the custom decode path does not yet produce displayable frames end-to-end.
