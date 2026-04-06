# ReelFin App Store Submission

## Release target

- Initial release path: iOS and iPadOS beta through TestFlight
- Bundle ID: `com.reelfin.app`
- Category: Entertainment
- Support email: `floriantaffin@gmail.com`
- Marketing URL: `https://flovflo.github.io/ReelFin/`
- Support URL: `https://flovflo.github.io/ReelFin/support.html`
- Privacy Policy URL: `https://flovflo.github.io/ReelFin/privacy.html`
- Terms of Service URL: `https://flovflo.github.io/ReelFin/terms.html`

## App description

ReelFin is a native iPhone and iPad client for Jellyfin built around Apple playback frameworks. Browse your library, pick up where you left off, and switch quickly between home recommendations, search, and detailed playback controls without a server-specific web wrapper.

Why ReelFin:

- Native playback path tuned for Apple devices
- Fast home feed with continue watching, next up, and recently added rails
- Detailed title pages with cast, seasons, episodes, and similar content
- Quality and playback controls for direct play, H.264 fallback, and diagnostics
- Secure session handling with token storage in the iOS Keychain

ReelFin is designed for users who want a cleaner, more deterministic Jellyfin experience on iOS and iPadOS, with playback behavior that stays close to the platform instead of relying on a generic embedded player.

Terms of Service: https://flovflo.github.io/ReelFin/terms.html
Privacy Policy: https://flovflo.github.io/ReelFin/privacy.html

## TestFlight beta information

- Beta App Description:
  ReelFin is a native beta client for self-hosted Jellyfin servers on iPhone and iPad.
- Feedback Email:
  `floriantaffin@gmail.com`
- What to Test:
  Sign in to a Jellyfin server, browse Home and Search, open detail pages, and validate playback start, resume state, subtitle selection, and playback stability on iPhone and iPad.
- Beta review notes:
  Use [Docs/AppReview-Notes.md](/Users/florian/Documents/Projet/ReelFin/Docs/AppReview-Notes.md) as the copy-ready template.

## App privacy answers

- Data linked to the user:
  - Contact info: support email only if the user chooses to contact support
  - User content: server URL and Jellyfin account session used to sign in
  - Diagnostics: crash reports if Sentry is configured at build time
- Data is not used for tracking
- Kids category: not targeted to children
- Suggested age rating: 13+ because the app can surface user-managed media libraries that may contain mature content

## Export compliance

- ReelFin uses standard Apple platform encryption only: HTTPS/TLS network transport and iOS Keychain storage.
- `ITSAppUsesNonExemptEncryption` is set to `NO` in the generated Info.plist for the app targets.
- App Store Connect export compliance answers still need to be confirmed on upload.

## Third-party SDK inventory

- GRDB via Swift Package Manager from `6.29.3`
- Sentry Cocoa via Swift Package Manager from `8.55.1`
- Local build resolution on April 5, 2026: `Sentry 8.58.0`, `GRDB 6.29.3`

## Review blockers that remain outside the repo

- App Store Connect app record creation or update
- App Privacy questionnaire answers in App Store Connect
- Beta App Review credentials for a working Jellyfin review server
- GitHub Pages deployment of the public support site before using the public URLs above
