"use client";

import type { CSSProperties, RefObject } from "react";
import type { SizePreset, SlideSpec } from "./studio";

type MarketingCanvasProps = {
  canvasRef?: RefObject<HTMLDivElement | null>;
  size: SizePreset;
  slide: SlideSpec;
};

export function MarketingCanvas({ canvasRef, size, slide }: MarketingCanvasProps) {
  const screenshotPath = `/docs-media/${slide.fileName}`;
  const canvasStyle = {
    "--canvas-width": `${size.width}px`,
    "--canvas-height": `${size.height}px`,
    "--surface-base": slide.palette.background,
    "--surface-soft": slide.palette.backgroundSoft,
    "--accent-start": slide.palette.accentStart,
    "--accent-end": slide.palette.accentEnd,
    "--glow-primary": slide.palette.glowPrimary,
    "--glow-secondary": slide.palette.glowSecondary
  } as CSSProperties;

  return (
    <div ref={canvasRef} className={`marketing-canvas slide-${slide.id} layout-${slide.layout}`} style={canvasStyle}>
      <div className="poster-surface">
        <img className="poster-ambient poster-ambient-full" src={screenshotPath} alt="" draggable={false} />
        <img className="poster-ambient poster-ambient-panel" src={screenshotPath} alt="" draggable={false} />
        <div className="copy-scrim" />
        <div className="poster-vignette" />

        <section className="poster-copy">
          <p className="poster-eyebrow">{slide.eyebrow}</p>
          <h1 className="poster-title">
            <span>{slide.title[0]}</span>
            <span className="accent-line">{slide.title[1]}</span>
          </h1>
          <p className="poster-body">{slide.body}</p>
        </section>

        <figure className="device-stage">
          <div className="device-backdrop">
            <img className="device-backdrop-shot" src={screenshotPath} alt="" draggable={false} />
          </div>
          <div className="device-shadow" />
          <div className="iphone-shell">
            <span className="iphone-button iphone-button-volume-up" />
            <span className="iphone-button iphone-button-volume-down" />
            <span className="iphone-button iphone-button-action" />
            <span className="iphone-button iphone-button-side" />

            <div className="iphone-screen">
              <div className="iphone-island" />
              <img className="device-shot" src={screenshotPath} alt={`ReelFin ${slide.id} screen`} draggable={false} />
            </div>
          </div>
        </figure>
      </div>
    </div>
  );
}
