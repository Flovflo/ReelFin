# ReelFin Screenshot Studio

This mini app follows the `ParthJadhav/app-store-screenshots` repo flow:

- Next.js studio
- real ReelFin iPhone screenshots from `Docs/Media`
- premium editorial App Store slides
- measured iPhone hardware mockup from the screenshot skill repo
- export automation for the 4 Apple iPhone screenshot sizes

## Run locally

```bash
cd AppStore/ScreenshotStudio
bun install
bun run dev
```

Open [http://127.0.0.1:4300](http://127.0.0.1:4300).

## Export all screenshots

```bash
./scripts/export_marketing_screenshots.sh
```

Exports land in `AppStore/MarketingScreenshotsIOS/`.
