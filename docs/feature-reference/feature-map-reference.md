# Feature map: reference

How the alternative (DuoBar 1.1.0 from the Mac App Store, macOS 27) behaves, as observed. Each feature has a folder with a `feature.md` and, where the screen held no personal data, screenshots and frame strips. Frame strips were recorded at 60 fps and read left to right, top to bottom, one frame per tile unless a file says otherwise. What Twofold builds from this lives in [the Twofold feature map](../feature-map.md).

## Core flow

```
menu bar mark (ring · center · dots)
      │ click                       │ hover (Pro, off by default)
      ▼                             ▼
popover: one row per module     unfold into one icon per reading
      │ click a row                 │ click an icon
      ▼                             ▼
module page (crossfade, the popover resizes)
```

## Features

| # | Feature | Summary |
|---|---------|---------|
| 01 | [Menu bar mark](01-mark/feature.md) | One status item: a ring, a center glyph, and four dots, each showing a reading |
| 02 | [Unfold](02-unfold/feature.md) | The mark morphs into separate icons: the ring unrolls into a bar, the dots slide out |
| 03 | [Popover](03-popover/feature.md) | List of modules with values, each opening a page |
| 04 | [Battery](04-battery/feature.md) | Level, power source, Low Power Mode, health |
| 05 | [Wi-Fi](05-wifi/feature.md) | On/off switch, network list behind Location access |
| 06 | [Bluetooth](06-bluetooth/feature.md) | Paired devices, connection, battery |
| 07 | [Sound](07-sound/feature.md) | Volume slider in the row, output device picker |
| 08 | [Display](08-display/feature.md) | Keep awake, mirroring, resolution (from the website, not seen) |
| 09 | [Network activity](09-network/feature.md) | Rates and a one-minute graph |
| 10 | [Memory](10-memory/feature.md) | Activity Monitor's split |
| 11 | [CPU](11-cpu/feature.md) | Graph, user/system/idle, load, thermal state, uptime |
| 12 | [Disk](12-disk/feature.md) | Free space per volume |
| 13 | [Live moments](13-moments/feature.md) | The mark briefly shows an event with a label |
| 14 | [Indicator settings](14-indicator-settings/feature.md) | Slots, ring style, thickness, size, colors |
| 15 | [Popover settings and profiles](15-popover-settings-and-profiles/feature.md) | Row order and visibility, details line, profiles |
| 16 | [General settings](16-general-settings/feature.md) | Login, hover action, moments, experimental switching |

## Also in DuoBar, not covered by a folder

- **Pro.** A one-time in-app purchase unlocks unfold on hover, any metric in any slot, gradient and segmented rings, colors, moments, details and profiles. The Pro tab of Settings is an animated sales page whose cards loop demos of those features; those demos are where several frame strips here come from.
- **Website.** teekamsuthar.com/duobar describes nine modules (with Display); the installed 1.1.0 lists eight rows and has no Display row in its settings.

## Platform facts

- Mac App Store, sandboxed, macOS 14 or later, `LSUIElement` (no Dock icon).
- Asks for Bluetooth (`NSBluetoothAlwaysUsageDescription`) and Location (`NSLocationWhenInUseUsageDescription`, for Wi-Fi network names).
- The popover is a real `NSPopover` with an arrow (accessibility role "pop over"); its rows are buttons.
