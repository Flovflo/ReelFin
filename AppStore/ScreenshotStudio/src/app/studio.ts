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
  layout: "hero" | "offset" | "center";
  eyebrow: string;
  title: [string, string];
  body: string;
  palette: {
    background: string;
    backgroundSoft: string;
    accentStart: string;
    accentEnd: string;
    glowPrimary: string;
    glowSecondary: string;
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
    layout: "hero",
    eyebrow: "HOME",
    title: ["Your Jellyfin,", "refined."],
    body: "Continue watching, fresh releases, and the next thing to play.",
    palette: {
      background: "#f3eadf",
      backgroundSoft: "#e6d9c8",
      accentStart: "#af6f42",
      accentEnd: "#d6a176",
      glowPrimary: "rgba(38, 48, 67, 0.10)",
      glowSecondary: "rgba(195, 136, 90, 0.18)"
    }
  },
  {
    id: "detail",
    order: 2,
    fileName: "Detail_ios.PNG",
    layout: "center",
    eyebrow: "PLAYBACK",
    title: ["Made for", "playback."],
    body: "Rich detail, native controls, and the right context before you press play.",
    palette: {
      background: "#04050a",
      backgroundSoft: "#100d12",
      accentStart: "#fbfbff",
      accentEnd: "#d9b26b",
      glowPrimary: "rgba(73, 131, 194, 0.14)",
      glowSecondary: "rgba(212, 150, 70, 0.20)"
    }
  },
  {
    id: "library",
    order: 3,
    fileName: "Library_ios.PNG",
    layout: "offset",
    eyebrow: "LIBRARY",
    title: ["Large libraries,", "clear."],
    body: "Search quickly, filter cleanly, and keep every cover readable.",
    palette: {
      background: "#04050a",
      backgroundSoft: "#0b1117",
      accentStart: "#f4f7fc",
      accentEnd: "#78c6ff",
      glowPrimary: "rgba(92, 185, 255, 0.18)",
      glowSecondary: "rgba(214, 98, 76, 0.16)"
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
