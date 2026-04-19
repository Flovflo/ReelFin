# ReelFin App Store Submission

## Release target

- Initial release path: iPhone on iOS and Apple TV on tvOS through TestFlight
- Bundle ID: `com.reelfin.app`
- Category: Entertainment
- Support email: `florian.taffin.pro@gmail.com`
- Marketing URL: `https://flovflo.github.io/reelfin-site/`
- Support URL: `https://flovflo.github.io/reelfin-site/support.html`
- Privacy Policy URL: `https://flovflo.github.io/reelfin-site/privacy.html`
- Terms of Service URL: `https://flovflo.github.io/reelfin-site/terms.html`

## App description

Bring your Jellyfin library to life with ReelFin, a polished native way to watch on iPhone and Apple TV. It is built around Apple playback frameworks and focuses on fast browsing, rich detail pages, reliable resume, and predictable playback on your own server.

Why ReelFin:

- Beautiful browsing for movies and shows
- Continue Watching, Next Up, and recently added or released rails
- Rich detail pages with cast, actions, file details, and playback metadata
- Apple-native playback path tuned for smooth startup and predictable streaming
- Playback preferences and session state kept on-device

Requirements:

- A Jellyfin server must already be set up and reachable
- ReelFin connects directly to the server you choose
- The app does not provide or sell media content

Terms of Service: https://flovflo.github.io/reelfin-site/terms.html
Privacy Policy: https://flovflo.github.io/reelfin-site/privacy.html

## TestFlight beta information

- Beta App Description:
  ReelFin is a polished native Jellyfin client for iPhone and Apple TV.
- Feedback Email:
  `florian.taffin.pro@gmail.com`
- What to Test:
  Sign in to a Jellyfin server, browse Home and Search, open detail pages, and validate playback start, resume state, subtitle selection, and playback stability on iPhone and Apple TV.
- Beta review notes:
  Use [Docs/AppReview-Notes.md](/Users/florian/Documents/Projet/ReelFin/Docs/AppReview-Notes.md) as a worksheet, then paste live review credentials and notes into App Store Connect.

## Visual assets

- Current storefront screenshots are uploaded manually from the curated files kept in `AppStore/Screenshots/`
- The README animation asset lives at `Docs/Media/reelfin-transition.gif`
- Keep README and App Store media aligned whenever the UI changes materially

## App privacy answers

- Data linked to the user:
  - Contact info: support email only if the user chooses to contact support
  - User content: server URL, on-device account identity, and Jellyfin account session used to sign in
  - Diagnostics: crash reports if Sentry is configured at build time
- Data is not used for tracking
- Kids category: not targeted to children
- Suggested age rating: 13+ because the app can surface user-managed media libraries that may contain mature content

## Export compliance

- ReelFin uses standard Apple platform encryption only: HTTPS/TLS network transport and Apple Keychain storage.
- `ITSAppUsesNonExemptEncryption` is set to `NO` in the generated Info.plist for the app targets.
- The current App Store Connect builds report `usesNonExemptEncryption: false`.
- No App Encryption Documentation upload should be required unless a future build adds non-exempt or proprietary cryptography.

## Compliance panels

- Digital Services Act: account-level / seller-level requirement. This is not exposed in the public App Store Connect API used here and must be checked manually in App Store Connect.
- Vietnam Game License: not applicable. ReelFin is not a game.
- Regulated Medical Device: not applicable. ReelFin is in Entertainment and the age rating declaration does not use `Medical or Treatment Information`.
- App Store Server Notifications: not applicable right now. ReelFin has no In-App Purchases or auto-renewable subscriptions configured.
- App-Specific Shared Secret: not applicable right now. ReelFin has no auto-renewable subscriptions configured.

## Third-party SDK inventory

- GRDB via Swift Package Manager from `6.29.3`
- Sentry Cocoa via Swift Package Manager from `8.55.1`
- Local build resolution on April 5, 2026: `Sentry 8.58.0`, `GRDB 6.29.3`

## Review blockers that remain outside the repo

- App Store Connect app record creation or update
- App Privacy questionnaire answers in App Store Connect
- Beta App Review credentials for a working Jellyfin review server
- Digital Services Act trader verification if the developer account still shows it as incomplete
