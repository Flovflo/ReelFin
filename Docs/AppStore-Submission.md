# ReelFin App Store Submission

## App description

ReelFin is a native iPhone and iPad client for Jellyfin built around Apple playback frameworks. Browse your library, pick up where you left off, and switch quickly between home recommendations, search, and detailed playback controls without a server-specific web wrapper.

Why ReelFin:

- Native playback path tuned for Apple devices
- Fast home feed with continue watching, next up, and recently added rails
- Detailed title pages with cast, seasons, episodes, and similar content
- Quality and playback controls for direct play, H.264 fallback, and diagnostics
- Secure session handling with token storage in the iOS Keychain

ReelFin is designed for users who want a cleaner, more deterministic Jellyfin experience on iOS and iPadOS, with playback behavior that stays close to the platform instead of relying on a generic embedded player.

Character count: 915

## App privacy answers

- Data linked to the user:
  - Contact info: support email only if the user chooses to contact support
  - User content: server URL and Jellyfin account session used to sign in
  - Diagnostics: crash reports if Sentry is configured at build time
- Data not used for tracking
- Kids category: not targeted to children, so COPPA-specific kid targeting does not apply
- Suggested age rating: 13+ because the app surfaces media libraries that may contain mature content and user-generated server catalogs

## Third-party SDK inventory

- GRDB `6.29.3`
- Sentry Cocoa `8.55.1`

## Support

- Support email: `floriantaffin@gmail.com`
- Support URL: `https://github.com/Flovflo/ReelFin/blob/main/Docs/support.html`
- Privacy policy URL: `https://github.com/Flovflo/ReelFin/blob/main/Docs/privacy-policy.html`
- Terms of service URL: `https://github.com/Flovflo/ReelFin/blob/main/Docs/terms-of-service.html`
