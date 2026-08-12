# ReelFin App Review Notes

Use this worksheet to prepare both TestFlight beta review and App Store review notes.
Keep all live review credentials out of Git, local artifacts, logs, and copied command lines.

## Contact

- Support email: `florian.taffin.pro@gmail.com`

## Review account

- Server URL: supplied securely at submission time through `REELFIN_REVIEW_SERVER_URL`
- Username: supplied securely at submission time through `REELFIN_REVIEW_USERNAME`
- Password: supplied securely at submission time through `REELFIN_REVIEW_PASSWORD`

The release operator must provide those three values as ephemeral environment input only.
Never replace the lines above with live values or commit a populated copy of this file.

The review account activates a built-in demo library with fictional media data.
It does not expose personal user content.

## Review flow

1. Launch ReelFin.
2. Enter the securely supplied review server URL, then continue.
3. Sign in with the securely supplied review username and password.
4. From Home or Library, open any movie or show detail page.
5. Start playback and validate resume state, subtitles, and general playback stability.
6. Optionally open Settings to review playback preferences and account state.

## Notes for App Review

- ReelFin is a native client for self-hosted Jellyfin servers.
- The app does not sell or unlock digital content and does not use in-app purchase.
- Please use the supplied review account rather than a personal server.
- The supplied review account opens a built-in fictional demo library for review.
- Crash reporting is optional and disabled unless a Sentry DSN is configured for the release build.
