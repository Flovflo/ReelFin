# ReelFin TestFlight Launch Checklist

## Repo and build

- [ ] Run `scripts/preflight_testflight_release.sh`
- [ ] Run `xcodegen generate` after any `project.yml` change
- [ ] Build the `ReelFin` scheme for iOS simulator
- [ ] Run the unit and UI tests you intend to rely on for the beta
- [ ] Regenerate App Store screenshots if the UI changed

## App Store Connect

- [ ] Create or update the iOS app record for bundle ID `com.reelfin.app`
- [ ] Set category to Entertainment
- [ ] Set age rating to 13+ or stricter if the review server exposes mature content
- [ ] Set Marketing URL to `https://flovflo.github.io/ReelFin/`
- [ ] Set Support URL to `https://flovflo.github.io/ReelFin/support.html`
- [ ] Set Privacy Policy URL to `https://flovflo.github.io/ReelFin/privacy.html`
- [ ] Add Terms of Service link to the description or EULA field
- [ ] Confirm the App Privacy questionnaire answers match the current build

## TestFlight metadata

- [ ] Beta App Description:
  `ReelFin is a native beta client for self-hosted Jellyfin servers on iPhone and iPad.`
- [ ] Feedback Email:
  `floriantaffin@gmail.com`
- [ ] What to Test:
  `Sign in to a Jellyfin server, browse Home and Search, open detail pages, and validate playback start, resume state, subtitle selection, and playback stability on iPhone and iPad.`
- [ ] Upload the current screenshots if you want them visible in TestFlight

## Beta App Review

- [ ] Paste the template from [Docs/AppReview-Notes.md](/Users/florian/Documents/Projet/ReelFin/Docs/AppReview-Notes.md)
- [ ] Provide a working review server URL, username, and password
- [ ] Make sure the review server stays online during review
- [ ] Make sure the review account can access at least one movie and one series

## Compliance

- [ ] Confirm export compliance answers for a build that uses standard Apple encryption only
- [ ] Confirm the support site is deployed and reachable over HTTPS
- [ ] Confirm screenshots use fictional or licensed library data
- [ ] Confirm there is no placeholder text in metadata, review notes, or TestFlight fields
