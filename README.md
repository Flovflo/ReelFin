# ReelFin iOS 🎬

ReelFin is a native iOS streaming client for Jellyfin, meticulously built with pure Swift and SwiftUI. It prioritizes Apple's native frameworks to deliver the fastest, most battery-efficient media playback experience possible.
---<img width="1206" height="2622" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-22 at 21 49 17" src="https://github.com/user-attachments/assets/a0636853-167b-4ff4-a8e0-61ade49aa04c" />
<img width="1206" height="2622" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-22 at 21 48 49" src="https://github.com/user-attachments/assets/d310c50e-8393-4cb2-bb88-f2e2222fd4ae" />



## Release: v2.0.1

This release brings polished UI refinements and deeper Jellyfin integration, including a "Liquid Glass" watched status system and a rock-solid paging architecture for the home screen.

### Key Features
* **Liquid Glass Watched Indicators**: Native support for Jellyfin `UserData`, displaying sleek checkmarks and progress bars that blend into the UI with Apple's hallmark translucency.
* **Robust Carousel Paging**: Refactored the hero carousel using native `TabView` architecture, eliminating "ghosting" glitches and ensuring perfectly smooth auto-scrolling on iOS 17.
* **Native Apple Player Experience**: Utilizes `AVPlayerViewController` wrapped seamlessly in SwiftUI for native PiP, spatial audio, and subtitle support.
* **Intelligent Transcode Engine**: Custom `PlaybackDecisionEngine` interrogates Jellyfin to automatically request `.fmp4` containers for blazing-fast hardware HEVC decoding.
* **HLS Race-Condition Immunity**: Implements a robust `Coordinator` layer that KVO-observes `readyToPlay` networks states, guaranteeing iOS's RemoteXPC video pipeline never times out or drops to a black screen.

### Architecture Highlights
* **Pure Swift 6 & Structured Concurrency**: Built from the ground up utilizing `async/await` and Actors for a thread-safe UI loop.
* **Decoupled Playback Engine**: `PlaybackSessionController` isolates AVKit logic from the UI layer.
* **Dynamic Network Watchdogs**: Automatic sync recovery mechanisms ensure uninterrupted viewing experiences.



*Built for iOS 16+*
