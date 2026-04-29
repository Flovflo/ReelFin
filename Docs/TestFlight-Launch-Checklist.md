# ReelFin TestFlight Launch Checklist

## Repo and build

- [ ] Run `scripts/preflight_testflight_release.sh`
- [ ] Run `xcodegen generate` after any `project.yml` change
- [ ] Confirm the beta 1 binary is version `0.1` build `10` or newer
- [ ] Build the `ReelFin` scheme for iOS simulator
- [ ] Run the unit and UI tests you intend to rely on for the beta
- [ ] Refresh `README.md` media if the storefront UI changed materially

## App Store Connect

- [ ] Create or update the app record for bundle ID `com.reelfin.app`
- [ ] Set category to Entertainment
- [ ] Set age rating to 13+ or stricter if the review server exposes mature content
- [ ] Set Marketing URL to `https://flovflo.github.io/reelfin-site/`
- [ ] Set Support URL to `https://flovflo.github.io/reelfin-site/support.html`
- [ ] Set Privacy Policy URL to `https://flovflo.github.io/reelfin-site/privacy.html`
- [ ] Add Terms of Service link to the description or EULA field
- [ ] Confirm the App Privacy questionnaire answers match the current build

## TestFlight metadata

- [ ] Create an internal TestFlight group first
- [ ] Create an External TestFlight group for public beta testers
- [ ] Enable a public invitation link for the external group after TestFlight App Review approval
- [ ] Beta App Description:
  `ReelFin is a native beta client for self-hosted Jellyfin servers on iPhone, iPad, and Apple TV.`
- [ ] Feedback Email:
  `florian.taffin.pro@gmail.com`
- [ ] What to Test:
  `Sign in to a Jellyfin server, browse Home and Search, open detail pages, and validate playback start, resume state, subtitle selection, and playback stability on iPhone, iPad, and Apple TV.`
- [ ] Upload the current screenshots if you want them visible in TestFlight

## Media sanity check

- [ ] Confirm any manually uploaded TestFlight/App Store screenshots match the current iPhone, iPad, and Apple TV UI
- [ ] Confirm `Docs/Media/reelfin-transition.gif` still reflects the app flow shown in `README.md`
- [ ] Confirm screenshot and README media use fictional or licensed library data only

## Beta App Review

- [ ] Copy the structure from [Docs/AppReview-Notes.md](/Users/florian/Documents/Projet/ReelFin/Docs/AppReview-Notes.md) into App Store Connect and replace every field with live review data
- [ ] Provide the built-in review demo server URL, username, and password from the review notes
- [ ] Make sure the review account can access at least one movie and one series in the built-in demo library

## Compliance

- [ ] Confirm export compliance answers for a build that uses standard Apple encryption only
- [ ] Confirm the support site is deployed and reachable over HTTPS
- [ ] Confirm there is no placeholder text in metadata, review notes, or TestFlight fields
- [ ] Upload a normal App Store Connect build, not a build marked TestFlight Internal Only
