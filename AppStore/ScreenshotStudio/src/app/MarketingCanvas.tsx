"use client";

import type { CSSProperties, RefObject } from "react";
import type { SizePreset, SlideSpec } from "./studio";

type MarketingCanvasProps = {
  canvasRef?: RefObject<HTMLDivElement | null>;
  size: SizePreset;
  slide: SlideSpec;
};

function SupportGroup({ slide }: { slide: SlideSpec }) {
  if (slide.support.variant === "library") {
    return (
      <div className="support-group support-library">
        <div className="support-toggle">
          <span className="support-chip is-active">{slide.support.items[0]}</span>
          <span className="support-chip">{slide.support.items[1]}</span>
        </div>
        <div className="support-search-pill">{slide.support.items[2]}</div>
      </div>
    );
  }

  return (
    <div className={`support-group support-${slide.support.variant}`}>
      {slide.support.items.map((item, index) => (
        <span key={item} className={`support-chip ${index === 0 ? "is-active" : ""}`}>
          {item}
        </span>
      ))}
    </div>
  );
}

export function MarketingCanvas({ canvasRef, size, slide }: MarketingCanvasProps) {
  const screenshotPath = `/docs-media/${slide.fileName}`;
  const canvasStyle = {
    "--canvas-width": `${size.width}px`,
    "--canvas-height": `${size.height}px`,
    "--surface-base": slide.palette.background,
    "--surface-soft": slide.palette.backgroundSoft,
    "--ink": slide.palette.ink,
    "--muted": slide.palette.muted,
    "--accent": slide.palette.accent,
    "--accent-soft": slide.palette.accentSoft,
    "--glow-primary": slide.palette.glowPrimary,
    "--glow-secondary": slide.palette.glowSecondary,
    "--copy-top": `${slide.composition.copy.top}%`,
    "--copy-left": `${slide.composition.copy.left}%`,
    "--copy-width": `${slide.composition.copy.width}%`,
    "--device-top": `${slide.composition.device.top}%`,
    "--device-right": `${slide.composition.device.right}%`,
    "--device-height": `${slide.composition.device.height}%`,
    "--device-rotate": `${slide.composition.device.rotation}deg`
  } as CSSProperties;

  return (
    <div ref={canvasRef} className={`marketing-canvas slide-${slide.id}`} style={canvasStyle}>
      <div className="poster-surface">
        <img className="poster-ambient poster-ambient-full" src={screenshotPath} alt="" draggable={false} />
        <img className="poster-ambient poster-ambient-panel" src={screenshotPath} alt="" draggable={false} />
        <div className="poster-vignette" />
        <div className="copy-scrim" />

        <section className="poster-copy">
          <p className="poster-eyebrow">{slide.eyebrow}</p>
          <h1 className="poster-title">
            <span>{slide.title[0]}</span>
            <span className="title-pill">{slide.title[1]}</span>
          </h1>
          <p className="poster-body">{slide.body}</p>
          <SupportGroup slide={slide} />
        </section>

        <figure className="device-stage">
          <div className="device-aura">
            <img className="device-aura-shot" src={screenshotPath} alt="" draggable={false} />
          </div>
          <div className="device-shadow" />
          <div className="iphone-shell">
            <span className="iphone-button iphone-button-action" />
            <span className="iphone-button iphone-button-volume-up" />
            <span className="iphone-button iphone-button-volume-down" />
            <span className="iphone-button iphone-button-side" />

            <div className="iphone-screen">
              <div className="iphone-speaker" />
              <div className="iphone-island" />
              <img className="device-shot" src={screenshotPath} alt={`ReelFin ${slide.id} screen`} draggable={false} />
            </div>
          </div>
        </figure>
      </div>
    </div>
  );
}
