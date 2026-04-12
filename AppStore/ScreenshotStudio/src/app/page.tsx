"use client";

import { toPng } from "html-to-image";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useMemo, useRef, useState, useTransition } from "react";
import { MarketingCanvas } from "./MarketingCanvas";
import { DEFAULT_SLIDE, SLIDES, getDevice, getSize, getSlide } from "./studio";

function StudioPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const exportMode = searchParams.get("export") === "1";
  const requestedDevice = getDevice();
  const requestedSlide = getSlide(searchParams.get("slide"));
  const requestedSize = getSize(requestedDevice, searchParams.get("size"));
  const canvasRef = useRef<HTMLDivElement>(null);
  const [previewScale, setPreviewScale] = useState(1);
  const [isPending, startTransition] = useTransition();

  useEffect(() => {
    document.body.dataset.exportMode = exportMode ? "true" : "false";
    return () => {
      delete document.body.dataset.exportMode;
    };
  }, [exportMode]);

  useEffect(() => {
    if (exportMode) {
      setPreviewScale(1);
      return;
    }

    const updateScale = () => {
      const widthBudget = window.innerWidth - 96;
      const heightBudget = window.innerHeight - 186;
      const nextScale = Math.min(widthBudget / requestedSize.width, heightBudget / requestedSize.height, 1);
      setPreviewScale(nextScale);
    };

    updateScale();
    window.addEventListener("resize", updateScale);
    return () => window.removeEventListener("resize", updateScale);
  }, [exportMode, requestedSize.height, requestedSize.width]);

  const updateParams = (updates: Record<string, string>) => {
    const next = new URLSearchParams(searchParams.toString());

    Object.entries(updates).forEach(([key, value]) => {
      next.set(key, value);
    });

    if (!next.get("slide")) {
      next.set("slide", DEFAULT_SLIDE);
    }

    router.replace(`/?${next.toString()}`, { scroll: false });
  };

  const preloadCanvasImages = async () => {
    const node = canvasRef.current;
    if (!node) {
      throw new Error("Canvas not ready");
    }

    await document.fonts.ready;

    const images = Array.from(node.querySelectorAll("img"));
    await Promise.all(
      images.map(
        (image) =>
          new Promise<void>((resolve) => {
            if (image.complete && image.naturalWidth > 0) {
              resolve();
              return;
            }

            const done = () => resolve();
            image.addEventListener("load", done, { once: true });
            image.addEventListener("error", done, { once: true });
          })
      )
    );
  };

  const renderPng = async () => {
    const node = canvasRef.current;
    if (!node) {
      throw new Error("Canvas not ready");
    }

    await preloadCanvasImages();

    const options = {
      backgroundColor: "#04050a",
      cacheBust: true,
      canvasWidth: requestedSize.width,
      canvasHeight: requestedSize.height,
      pixelRatio: 1
    };

    await toPng(node, options);
    return toPng(node, options);
  };

  useEffect(() => {
    if (!exportMode) {
      delete document.body.dataset.ready;
      return;
    }

    let cancelled = false;
    document.body.dataset.ready = "false";

    const markReady = async () => {
      try {
        await preloadCanvasImages();
        if (!cancelled) {
          document.body.dataset.ready = "true";
        }
      } catch (error) {
        console.error(error);
      }
    };

    void markReady();

    return () => {
      cancelled = true;
      document.body.dataset.ready = "false";
    };
  }, [exportMode, requestedSize.height, requestedSize.width, requestedSlide.id]);

  const handleDownload = async () => {
    const url = await renderPng();
    const link = document.createElement("a");
    link.href = url;
    link.download = `${String(requestedSlide.order).padStart(2, "0")}-${requestedSlide.id}.png`;
    link.click();
  };

  const orderedSlides = useMemo(() => SLIDES, []);

  if (exportMode) {
    return (
      <main className="export-shell">
        <MarketingCanvas canvasRef={canvasRef} size={requestedSize} slide={requestedSlide} />
      </main>
    );
  }

  return (
    <main className="studio-shell">
      <section className="studio-intro">
        <p className="intro-eyebrow">ParthJadhav / app-store-screenshots flow</p>
        <h1>Docs iOS captures, rebuilt in a warmer editorial App Store vibe.</h1>
        <p>
          This studio only uses the three iPhone screenshots in <code>Docs/Media</code> and exports a cleaner iOS-only set.
        </p>
      </section>

      <section className="studio-toolbar">
        <label>
          Size
          <select
            value={requestedSize.id}
            onChange={(event) =>
              startTransition(() => {
                updateParams({ size: event.target.value });
              })
            }
          >
            {requestedDevice.sizes.map((size) => (
              <option key={size.id} value={size.id}>
                {size.label} ({size.width}×{size.height})
              </option>
            ))}
          </select>
        </label>

        <label>
          Slide
          <select
            value={requestedSlide.id}
            onChange={(event) =>
              startTransition(() => {
                updateParams({ slide: event.target.value });
              })
            }
          >
            {orderedSlides.map((slide) => (
              <option key={slide.id} value={slide.id}>
                {slide.order}. {slide.eyebrow}
              </option>
            ))}
          </select>
        </label>

        <button type="button" onClick={handleDownload} disabled={isPending}>
          Export current PNG
        </button>
      </section>

      <section className="preview-shell">
        <div className="preview-scale" style={{ transform: `scale(${previewScale})` }}>
          <MarketingCanvas canvasRef={canvasRef} size={requestedSize} slide={requestedSlide} />
        </div>
      </section>
    </main>
  );
}

export default function HomePage() {
  return (
    <Suspense fallback={null}>
      <StudioPage />
    </Suspense>
  );
}
