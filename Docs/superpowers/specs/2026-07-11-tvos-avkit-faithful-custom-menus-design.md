# tvOS AVKit-Faithful Custom Player Menus

Date: 2026-07-11
Status: approved visual direction; awaiting written-spec review

## Objective

Keep ReelFin's custom tvOS playback engine, seek behavior, Jellyfin track switching, focus ownership, and crash fixes. Replace only the custom Audio and Subtitles menu presentation with a faithful manual reproduction of the AVKit iOS menus supplied by the user.

The implementation must look like Apple playback UI, not like a generic ReelFin list, while remaining fully custom and compatible with both ReelFin playback routes.

## Reference Contract

The visual references are:

- `/var/folders/yf/zz_rknnj5x34t8lg78gjx76m0000gn/T/codex-clipboard-055547a3-25c0-46d7-82ba-38215f5b6653.png`
- `/var/folders/yf/zz_rknnj5x34t8lg78gjx76m0000gn/T/codex-clipboard-a87c900e-6a00-4fbf-b7c5-9b74dd5b11f2.png`

Required visual characteristics:

- A single blue-grey translucent Liquid Glass card with a thin luminous edge.
- Large continuous corner radius and generous internal margins.
- No black opaque fill, row-by-row dark capsules, or generic `List` styling.
- Section title in a smaller secondary style.
- Primary options displayed as spacious text rows.
- A selected option uses a leading checkmark; focus is a restrained translucent white wash, not a full-white pill.
- Navigation rows show a large primary label, smaller current value underneath, and a trailing chevron.
- A subtle divider separates On/Off from Language and Style.
- Card scale, blur, tint, typography, and spacing remain consistent between Audio and Subtitles.

## Component Architecture

### Shared menu shell

`NativePlayerAVKitStyleMenuCard` owns the common Liquid Glass surface, geometry, transition, accessibility container, and focus scope. It accepts a menu page model and renders rows without knowing Jellyfin APIs.

Target tvOS metrics at 1920×1080:

- Width: 600 points.
- Corner radius: 44 points.
- Horizontal inset: 54 points.
- Vertical inset: 42 points.
- Header: 30-point semibold, secondary white.
- Primary row: 34-point regular/medium.
- Secondary value: 22-point regular, reduced opacity.
- Row height: 68 points for simple choices; 108 points for navigation rows.
- Divider: 1 point, low-opacity white.
- Focus wash: white opacity around 0.16–0.22, clipped to a continuous rounded rectangle.
- Surface: native `.glassEffect(.regular.tint(...), in: .rect(cornerRadius: 44))`; no opaque backing fill.

### Audio page

The root page title is `Audio Track`. It presents every real `audioOption` as one spacious language row. The active option has a leading checkmark. Selecting a row calls the existing `.audio(trackID)` path, closes the menu, and restores focus to the Audio chrome button.

If there is no alternative audio option, the Audio chrome button stays hidden under the existing availability policy.

### Subtitles root page

The root page title is `Subtitles` and contains:

1. `On`
2. `Off`
3. Divider
4. `Language` with the active language value and chevron
5. `Style` with the active style value and chevron

`Off` calls `.subtitle(nil)`. `On` restores the last selected subtitle track when still available; otherwise it chooses the default, then forced, then first real track. The active On/Off state has a leading checkmark.

### Language submenu

The Language submenu lists all real Jellyfin subtitle options using localized language names and concise metadata. Selecting a track calls the existing `.subtitle(trackID)` path, updates the root-page value, and returns to the root Subtitles page without dismissing the entire player.

Duplicate language variants remain distinguishable by concise metadata such as `Forced`, `SDH`, or codec. Track IDs never appear in labels or logs.

### Style submenu

Every displayed Style row must perform a real action. Initial styles:

- `Transparent Background`: text with shadow and no filled caption box.
- `Subtle Background`: text with a low-opacity rounded background.

The selected style has a checkmark. The setting applies to ReelFin-rendered sidecar and native sample-buffer subtitles and is persisted through the existing settings storage pattern. AVKit-rendered subtitles remain system-owned.

## Focus And Remote Behavior

- Opening a menu moves focus to the selected row, or the first available row.
- Up/Down moves exactly one visible row and is bounded.
- Select performs the row action exactly once.
- Right or Select on Language/Style opens its submenu.
- Left or Menu in a submenu returns to the Subtitles root page.
- Menu on a root page closes the card and restores the originating Audio/Subtitles button.
- The chrome behind the menu remains non-interactive but its stable focus scope is not destroyed or remounted.
- All focus handoffs use state tokens plus `Task.yield()`, never fixed sleeps.

## Data Flow

The menu consumes the existing `PlaybackControlsModel`. New pure presentation state stores only:

- current page (`audio`, `subtitlesRoot`, `subtitleLanguages`, `subtitleStyles`),
- focused row identifier,
- last enabled subtitle track identifier,
- chosen ReelFin subtitle style.

Track selection continues through `PlaybackControlSelection`; CustomPlayer and NativePlayer keep their existing selection/reload implementations. No menu code constructs playback URLs or calls Jellyfin directly.

## Error And Edge Behavior

- Options that cannot perform a real action are omitted.
- A track disappearing during reload returns focus to the first valid option.
- A failed track reload leaves the player visible and exposes the existing playback error state; the menu never claims selection before transport state confirms it.
- Long labels use one primary line plus one secondary metadata line with bounded scaling; no horizontal truncation of the language itself.
- Empty Audio/Subtitles capabilities cannot open an empty card.

## Platform Isolation

- The new card is tvOS-only.
- iOS keeps native AVKit controls, the recently corrected audio-session behavior, and compact subtitle presentation.
- Both tvOS CustomPlayer and NativePlayer routes use the same menu component and state machine.

## Verification

TDD must cover:

- exact geometry and Liquid Glass configuration;
- Audio rows and active checkmark;
- Subtitles On/Off, Language, and Style hierarchy;
- last-track restoration and fallback choice;
- submenu and Menu/Left navigation;
- focus bounds and origin restoration;
- every rendered row mapping to a real action;
- style application to both ReelFin subtitle renderers;
- iOS compilation and unchanged iOS policy.

Live validation uses the authenticated tvOS simulator and Star City S1E1 without reset/uninstall/sign-out. It must change audio and subtitles, navigate both submenus, change subtitle style, restore focus, seek, and return to Detail without error. Captures of Audio, Subtitles root, Language, and Style are compared against the supplied references before approval.

