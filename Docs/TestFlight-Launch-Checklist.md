# ReelFin TestFlight Launch Checklist

## Repo and build

- [ ] Run `scripts/preflight_testflight_release.sh`
- [ ] Run `xcodegen generate` after any `project.yml` change
- [ ] Build the `ReelFin` scheme for iOS simulator
- [ ] Run the unit and UI tests you intend to rely on for the beta
- [ ] Refresh `README.md` media if the storefront UI changed materially

## App Store Connect

- [ ] Create or update the iOS app record for bundle ID `com.reelfin.app`
- [ ] Set category to Entertainment
- [ ] Set age rating to 13+ or stricter if the review server exposes mature content
- [ ] Set Marketing URL to `https://flovflo.github.io/reelfin-site/`
- [ ] Set Support URL to `https://flovflo.github.io/reelfin-site/support.html`
- [ ] Set Privacy Policy URL to `https://flovflo.github.io/reelfin-site/privacy.html`
- [ ] Add Terms of Service link to the description or EULA field
- [ ] Confirm the App Privacy questionnaire answers match the current build

## TestFlight metadata

- [ ] Beta App Description:
  `ReelFin is a native beta client for self-hosted Jellyfin servers on iPhone and Apple TV.`
- [ ] Feedback Email:
  `florian.taffin.pro@gmail.com`
- [ ] What to Test:
  `Sign in to a Jellyfin server, browse Home and Search, open detail pages, and validate playback start, resume state, subtitle selection, and playback stability on iPhone and Apple TV.`
- [ ] Upload the current screenshots if you want them visible in TestFlight

## Media sanity check

- [ ] Confirm the curated files in `AppStore/Screenshots/` match the current iPhone and Apple TV UI before manual upload
- [ ] Confirm `Docs/Media/reelfin-transition.gif` still reflects the app flow shown in `README.md`
- [ ] Confirm screenshot and README media use fictional or licensed library data only

## Beta App Review

- [ ] Copy the structure from [Docs/AppReview-Notes.md](/Users/florian/Documents/Projet/ReelFin/Docs/AppReview-Notes.md) into App Store Connect and replace every field with live review data
- [ ] Provide a working review server URL, username, and password outside the repo
- [ ] Make sure the review server stays online during review
- [ ] Make sure the review account can access at least one movie and one series

## Compliance

- [ ] Confirm export compliance answers for a build that uses standard Apple encryption only
- [ ] Confirm the support site is deployed and reachable over HTTPS
- [ ] Confirm there is no placeholder text in metadata, review notes, or TestFlight fields
