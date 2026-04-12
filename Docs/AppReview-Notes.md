# ReelFin App Review Notes

Use this worksheet to prepare both TestFlight beta review and App Store review notes.
Do not paste this file verbatim into App Store Connect. Replace every field with live review information before submission.

## Contact

- Support email: `floriantaffin@gmail.com`

## Review account

- Server URL: provide the live Jellyfin review server URL in App Store Connect
- Username: provide the dedicated review username in App Store Connect
- Password: provide the dedicated review password in App Store Connect

## Review flow

1. Launch ReelFin.
2. Enter the review server URL, then continue.
3. Sign in with the review username and password.
4. From Home or Library, open any movie or show detail page.
5. Start playback and validate resume state, subtitles, and general playback stability.
6. Optionally open Settings to review playback preferences and account state.

## Notes for App Review

- ReelFin is a native client for self-hosted Jellyfin servers.
- The app does not sell or unlock digital content and does not use in-app purchase.
- The app requires a reachable Jellyfin server during review, so the review server above must stay online.
- Please use the supplied review account rather than a personal server.
- Crash reporting is optional and disabled unless a Sentry DSN is configured for the release build.
