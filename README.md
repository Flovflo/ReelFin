<div align="center">
  <img src="ReelFinApp/Resources/ReelFinIcon.icon/Assets/reelfinlogo.png" alt="ReelFin icon" width="112" height="112">
  <h1>ReelFin</h1>
  <p><strong>Native Jellyfin client for Apple platforms.</strong></p>
</div>

ReelFin is a native Jellyfin client built with SwiftUI, AVFoundation, and AVKit. The repository is organized as a modular XcodeGen project, with `project.yml` as the source of truth for targets, schemes, and build settings.

## Current Scope

- Native app targets for iPhone and Apple TV
- SwiftUI interface and platform-specific presentation layers
- Jellyfin networking client and DTO decoding
- Apple-native playback engine, subtitles, and local HLS support
- Local persistence, image caching, and background sync modules
- Unit and UI test targets

## Project Map

- `ReelFinApp/`: app entry points and platform bootstrap
- `ReelFinUI/`: SwiftUI screens, components, and presentation logic
- `PlaybackEngine/`: playback planning, player bridge, subtitles, and streaming helpers
- `JellyfinAPI/`: Jellyfin networking client and models
- `DataStore/`: local persistence with GRDB
- `ImageCache/`: memory and disk image pipeline
- `SyncEngine/`: background sync orchestration
- `Shared/`: shared models, protocols, settings, and logging
- `Tests/`: unit and UI tests
- `Docs/`: playback, release, and support documentation

## Build And Test

### Requirements

- Xcode with the required iOS and tvOS simulator runtimes installed
- XcodeGen

### Generate The Project

```bash
xcodegen generate
```

### Build iOS

```bash
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

### Build tvOS

```bash
xcodebuild build -project ReelFin.xcodeproj -scheme ReelFinTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=26.2'
```

### Test iOS

```bash
xcodebuild test -project ReelFin.xcodeproj -scheme ReelFin \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```

If your local simulator names or OS versions differ, replace the destination values accordingly.

## Documentation

- [Docs/README.md](Docs/README.md)
- [Docs/Playback-Architecture-Current.md](Docs/Playback-Architecture-Current.md)
- [Docs/AppStore-Submission.md](Docs/AppStore-Submission.md)
- [Docs/TestFlight-Launch-Checklist.md](Docs/TestFlight-Launch-Checklist.md)
- [Docs/AppReview-Notes.md](Docs/AppReview-Notes.md)

## License

The ReelFin source code in this repository is source-available under [PolyForm Noncommercial 1.0.0](LICENSE). You can use, modify, and share the code for non-commercial purposes.

Commercial use, resale, or inclusion in a paid product or service requires prior written permission.

The ReelFin name, logo, app icon, screenshots, documentation, and other original brand or media assets are not covered by that code license and remain protected unless a file says otherwise. See [COPYRIGHT.md](COPYRIGHT.md).
