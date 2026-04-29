# ReelFin App Review Notes

Use this worksheet to prepare both TestFlight beta review and App Store review notes.
Do not paste this file verbatim into App Store Connect. Replace every field with live review information before submission.

## Contact

- Support email: `florian.taffin.pro@gmail.com`

## Review account

- Server URL: `https://review.reelfin.app`
- Username: `review`
- Password: `ReelFin-Review-2026`

The review account activates a built-in demo library with fictional media data.
It does not require a live Jellyfin server and does not expose user content.

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
- Please use the supplied review account rather than a personal server.
- The supplied review account opens a built-in fictional demo library for review.
- Crash reporting is optional and disabled unless a Sentry DSN is configured for the release build.
