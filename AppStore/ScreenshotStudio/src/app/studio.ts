export type DeviceKey = "iphone";
export type SlideKey = "home" | "library" | "detail";

export type SizePreset = {
  id: string;
  label: string;
  folder: string;
  width: number;
  height: number;
};

export type DeviceSpec = {
  key: DeviceKey;
  label: string;
  screenshotBasePath: string;
  defaultSizeId: string;
  sizes: SizePreset[];
};

export type SlideSpec = {
  id: SlideKey;
  order: number;
  fileName: string;
  eyebrow: string;
  title: [string, string];
  body: string;
  palette: {
    background: string;
    backgroundSoft: string;
    ink: string;
    muted: string;
    accent: string;
    accentSoft: string;
    glowPrimary: string;
    glowSecondary: string;
  };
  composition: {
    copy: {
      top: number;
      left: number;
      width: number;
    };
    device: {
      top: number;
      right: number;
      height: number;
      rotation: number;
    };
  };
  support: {
    variant: "home" | "detail" | "library";
    items: string[];
  };
};

export const DEVICES: Record<DeviceKey, DeviceSpec> = {
  iphone: {
    key: "iphone",
    label: "iPhone",
    screenshotBasePath: "/docs-media",
    defaultSizeId: "iphone-6.9",
    sizes: [
      { id: "iphone-6.9", label: '6.9"', folder: "iphone-6.9-inch", width: 1320, height: 2868 },
      { id: "iphone-6.5", label: '6.5"', folder: "iphone-6.5-inch", width: 1284, height: 2778 },
      { id: "iphone-6.3", label: '6.3"', folder: "iphone-6.3-inch", width: 1206, height: 2622 },
      { id: "iphone-6.1", label: '6.1"', folder: "iphone-6.1-inch", width: 1125, height: 2436 }
    ]
  }
};

export const SLIDES: SlideSpec[] = [
  {
    id: "home",
    order: 1,
    fileName: "Home-ios.PNG",
    eyebrow: "HOME FEED",
    title: ["Pick up where", "you left off"],
    body: "A cinematic home feed for everything waiting in your library.",
    palette: {
      background: "#05070c",
      backgroundSoft: "#0a0e15",
      ink: "#fbf7ef",
      muted: "rgba(229, 223, 214, 0.80)",
      accent: "#e3be82",
      accentSoft: "#9a6936",
      glowPrimary: "rgba(252, 111, 44, 0.34)",
      glowSecondary: "rgba(85, 118, 225, 0.24)"
    },
    composition: {
      copy: { top: 10.6, left: 8.8, width: 36 },
      device: { top: 33, right: 4.9, height: 61, rotation: -1.4 }
    },
    support: {
      variant: "home",
      items: ["Continue Watching", "Recently Released"]
    }
  },
  {
    id: "detail",
    order: 2,
    fileName: "Detail_ios.PNG",
    eyebrow: "DETAIL & PLAYBACK",
    title: ["Press play", "with context"],
    body: "Formats, subtitles, and rich detail before you commit.",
    palette: {
      background: "#040507",
      backgroundSoft: "#0a0d12",
      ink: "#fbf8f2",
      muted: "rgba(228, 231, 236, 0.78)",
      accent: "#ead29d",
      accentSoft: "#8f7248",
      glowPrimary: "rgba(225, 175, 87, 0.30)",
      glowSecondary: "rgba(65, 140, 160, 0.20)"
    },
    composition: {
      copy: { top: 10.2, left: 8.8, width: 34 },
      device: { top: 28.6, right: 4.7, height: 62.4, rotation: 0.8 }
    },
    support: {
      variant: "detail",
      items: ["4K", "Dolby Atmos", "Subtitles"]
    }
  },
  {
    id: "library",
    order: 3,
    fileName: "Library_ios.PNG",
    eyebrow: "LIBRARY",
    title: ["Browse your", "whole library"],
    body: "Fast filters, clear artwork, and search that stays readable.",
    palette: {
      background: "#040509",
      backgroundSoft: "#090d14",
      ink: "#fbf8f3",
      muted: "rgba(229, 234, 242, 0.78)",
      accent: "#d9b272",
      accentSoft: "#7e6340",
      glowPrimary: "rgba(214, 78, 58, 0.28)",
      glowSecondary: "rgba(90, 156, 221, 0.20)"
    },
    composition: {
      copy: { top: 10.4, left: 8.8, width: 35 },
      device: { top: 31.5, right: 4.2, height: 60.2, rotation: 1.1 }
    },
    support: {
      variant: "library",
      items: ["Movies", "Shows", "Search your library"]
    }
  }
];

export const DEFAULT_DEVICE: DeviceKey = "iphone";
export const DEFAULT_SLIDE: SlideKey = "home";

export function getDevice(): DeviceSpec {
  return DEVICES.iphone;
}

export function getSlide(key: string | null): SlideSpec {
  return SLIDES.find((slide) => slide.id === key) ?? SLIDES[0];
}

export function getSize(device: DeviceSpec, sizeId: string | null): SizePreset {
  return device.sizes.find((size) => size.id === sizeId) ?? device.sizes.find((size) => size.id === device.defaultSizeId) ?? device.sizes[0];
}
