<br/>
<div align="center">
<img src="https://raw.githubusercontent.com/jellyfin/jellyfin-ux/master/branding/SVG/icon-transparent.svg" alt="Jellyfin Logo" width="120" height="120">
<h1 align="center">ReelFin</h1>
<p align="center">
<strong>The Ultimate Native iOS & tvOS Client for Jellyfin</strong>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2026%2B%20%7C%20tvOS-blue.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange.svg" alt="Swift">
  <img src="https://img.shields.io/badge/Framework-SwiftUI-informational.svg" alt="SwiftUI">
  <img src="https://img.shields.io/badge/Status-Beta%20v0.3-success.svg" alt="Status">
</p>
</div>

---

**ReelFin** is a beautifully crafted, highly optimized, and meticulously engineered native client for Jellyfin, designed exclusively for the Apple ecosystem. 

Unlike other media players that rely on heavy, third-party libraries (like VLCKit, libVLC, or FFmpeg), ReelFin's playback strategy is deliberately tuned around **native Apple frameworks** (`AVFoundation`, `AVKit`, `VideoToolbox`). The result is a deterministic, debuggable stack that delivers maximum battery efficiency, fluid SwiftUI interfaces, and unparalleled performance.

## ✨ Key Features

- **Apple-Native Playback Engine**: Zero third-party decoding overhead. Everything flows through `AVPlayer` and hardware decoders for maximum efficiency.
- **Direct-Play First**: ReelFin rigorously attempts to direct-play compatible streams (MP4/fMP4, HEVC, AVC, AAC, HDR10, Dolby Vision) exactly as they exist on your server.
- **Native Bridge (On-Device Remuxing)**: Seamlessly handles MKV containers by repackaging them into fragmented MP4 (fMP4) on-the-fly, locally on your device, enabling native playback without server-side transcoding.
- **Next-Gen Format Support**: Fully supports 4K HEVC 10-bit, HDR10, and Dolby Vision (Profile 8.1), delivering a premium home theater experience.
- **Deterministic Fallback Profiles**: If a raw asset isn't Apple-compatible, the `PlaybackDecisionEngine` intelligently steps through precise profiles (`appleOptimizedHEVC`, `conservativeCompatibility`, `forceH264Transcode`) to guarantee successful playback.
- **Premium SwiftUI Interface**: A buttery-smooth, natively designed UI that feels right at home on your iPhone, iPad, and Apple TV. Look for glassmorphism, fluid micro-animations, and striking typography.
- **Advanced Diagnostics ("Nerd Overlay")**: For power users and developers, a built-in overlay surfaces real-time capability matrices, decision traces, and AVPlayer states.

---

## 🏗️ Architecture & Technical Context (For LLMs & Developers)

ReelFin is architected with clear boundaries and separation of concerns, making it an excellent codebase for AI-assisted development (LLMs) and advanced iOS engineering. The primary modules include:

### 1. Playback Engine (`PlaybackEngine`)
The brain of ReelFin. It evaluates media capabilities and manages the AVPlayer lifecycle.
- **`MediaSourceResolver`**: Interrogates Jellyfin for direct stream URLs and exact file metadata (container, codecs, bitrates, HDR data).
- **`PlaybackCapabilityEvaluator`**: Maps server metadata against the active iOS device's hardware decoding capabilities.
- **`PlaybackDecisionEngine`**: The core router. Chooses between `DirectPlay`, `Remux` (via Native Bridge), or `Transcode`.
- **`NativeBridge`**: A sophisticated local pipeline that demuxes incompatible containers (like MKV) and remuxes them into `AVAssetResourceLoaderDelegate`-friendly fMP4 chunks.
- **`PlaybackCoordinator` & `PlaybackSessionController`**: Handles the `AVPlayer` initialization, URL parameter normalization (HLS variants), and watchdog timers for fault recovery.

### 2. User Interface (`ReelFinUI`)
Built purely with modern declarative **SwiftUI**.
- Structured into cohesive feature domains: `Home`, `Library`, `Detail`, `Player`, `Login`, and `Settings`.
- Utilizes `ReelFinDependencies` for clean dependency injection, keeping views testable and previews reliable.

### 3. API Communication (`JellyfinAPI`)
A robust, Swift concurrency (`async/await`) powered network layer that interfaces with the Jellyfin server, handling authentication, pagination, and real-time playback reporting.

---

## ⚙️ Configuration & Settings

ReelFin puts you in control of your media playback:
- **Force Raw Direct Play**: Instructs the decision engine to bypass remuxing or transcoding if an Apple-compatible source is detected.
- **Force H264 Fallback**: Useful for older devices or AirPlay. Pins playback to stable, SDR H.264 streams (`forceH264Transcode`), ensuring maximum compatibility at the cost of HDR/HEVC features.
- **Debug Overlay (`reelfin.playback.debugOverlay.enabled`)**: Enable this in settings to display the playback trace directly on the video player. Perfect for debugging why a specific file is transcoding.

---

## 🛠️ Testing & Development

ReelFin relies heavily on automated testing to ensure the playback decision matrix remains intact. When modifying `PlaybackEngine`, ensure tests remain green.

```bash
# Run unit tests for the PlaybackEngine (iOS 26 Simulator recommended)
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=26.0' \
  -only-testing:PlaybackEngineTests/PlaybackDecisionEngineTests \
  -only-testing:PlaybackEngineTests/CapabilityEngineTests
```

### Extending Playback Policy
If you are extending the playback logic or adding new server fallback profiles:
1. Always consult `Docs/Playback-Architecture-Current.md` first.
2. Maintain the STRICT rule: **No non-native dependencies in the playback path.** Do not introduce VLCKit or embedded FFmpeg video decoders. Keep it pure.

---

## 📄 License & Contributing

Contributions are welcome! Whether you are improving the Native Bridge MKV parsing, adding tvOS enhancements, or fixing UI glitches, please ensure your PRs align with the Apple-native philosophy of this project.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

*Designed with ❤️ for Jellyfin & Apple ecosystem lovers.*
