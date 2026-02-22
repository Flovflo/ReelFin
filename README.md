# ReelFin iOS 🎬

ReelFin is a native iOS streaming client for Jellyfin, meticulously built with pure Swift and SwiftUI. It prioritizes Apple's native frameworks to deliver the fastest, most battery-efficient media playback experience possible.
<img width="380" height="568" alt="image" src="https://github.com/user-attachments/assets/f158ee58-b9f8-47bd-9122-058d9f446469" />
<img width="380" height="568" alt="image" src="https://github.com/user-attachments/assets/7b1f296b-1b21-407b-b048-97a04f737280" />


## Release: Beta 0.1

This initial beta release introduces a rock-solid foundation for video playback, solving complex AVPlayer rendering architectures with remote HLS transcodes.

### Key Features
* **Native Apple Player Experience**: Utilizes `AVPlayerViewController` wrapped seamlessly in SwiftUI for native PiP, spatial audio, and subtitle support.
* **Intelligent Transcode Engine**: Custom `PlaybackDecisionEngine` interrogates Jellyfin to automatically request `.fmp4` containers for blazing-fast hardware HEVC decoding.
* **HLS Race-Condition Immunity**: Implements a robust `Coordinator` layer that KVO-observes `readyToPlay` networks states, guaranteeing iOS's RemoteXPC video pipeline never times out or drops to a black screen during slow server-side transcodes.
* **Graceful Degradation**: Safely falls back to stable `.ts` containers for H264 streams when HEVC hardware acceleration is unsupported.

### Architecture Highlights
* **Pure Swift 6 & Structured Concurrency**: Built from the ground up utilizing `async/await` and Actors for a thread-safe UI loop.
* **Decoupled Playback Engine**: `PlaybackSessionController` isolates AVKit logic from the UI layer.
* **Dynamic Network Watchdogs**: Automatic sync recovery mechanisms ensure uninterrupted viewing experiences.

---
*Built for iOS 16+*
