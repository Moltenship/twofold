# Twofold feature map

Twofold is a small, native, open-source menu bar app for macOS: one live mark that folds battery, Wi-Fi and memory into a single status item, and a popover with real controls. This page says what Twofold builds, in what order, and what each feature must do. How the alternative does it, with frame strips, is in [the reference](feature-reference/feature-map-reference.md).

## Product in one paragraph

One status item replaces three. The ring, the center and the dots each carry a reading. Click it and it unfolds into one icon per reading with the same unrolling motion as the alternative; click an icon and its page opens. Everything is free, local, and private: no account, no purchase, no telemetry, no network calls.

## Features

**P0** is needed for a usable first release, **P1** is expected by people coming from the alternative, **P2** is nice to have.

| # | Feature | Priority | Reference |
|---|---------|----------|-----------|
| 01 | Menu bar mark | P0 | [01](feature-reference/01-mark/feature.md) |
| 02 | Unfold on click | P0 | [02](feature-reference/02-unfold/feature.md) |
| 03 | Popover and pages | P0 | [03](feature-reference/03-popover/feature.md) |
| 04 | Battery | P0 | [04](feature-reference/04-battery/feature.md) |
| 05 | Wi-Fi | P0 | [05](feature-reference/05-wifi/feature.md) |
| 06 | Bluetooth | P1 | [06](feature-reference/06-bluetooth/feature.md) |
| 07 | Sound | P0 | [07](feature-reference/07-sound/feature.md) |
| 08 | Display | P2 | [08](feature-reference/08-display/feature.md) |
| 09 | Network activity | P0 | [09](feature-reference/09-network/feature.md) |
| 10 | Memory | P0 | [10](feature-reference/10-memory/feature.md) |
| 11 | CPU | P0 | [11](feature-reference/11-cpu/feature.md) |
| 12 | Disk | P0 | [12](feature-reference/12-disk/feature.md) |
| 13 | Live moments | P1 | [13](feature-reference/13-moments/feature.md) |
| 14 | Indicator settings | P0 | [14](feature-reference/14-indicator-settings/feature.md) |
| 15 | Popover settings and profiles | P1 | [15](feature-reference/15-popover-settings-and-profiles/feature.md) |
| 16 | General settings | P0 | [16](feature-reference/16-general-settings/feature.md) |

## Release slices

1. **MVP:** 01, 02, 03, 04, 05, 07, 09, 10, 11, 12, 14, 16. The mark, unfold, and every popover page with its controls.
2. **Parity:** 06, 13, 15.
3. **Extras:** 08, joining Wi-Fi networks from the popover.

## Out of scope

- Unfold or popover on hover. Twofold responds to clicks only.
- Licensing, Pro, and the Pro sales tab. Everything the alternative sells is free.
- Telemetry, update checks, and any network access.
- Sandboxing and the App Store. Twofold is built from source and signed ad hoc.

## Requirements per feature

### 01 Menu bar mark
- Same geometry as the alternative: ring from 215° sweeping 256° clockwise, four dots on the same circle in the gap, glyph or number in the center. Sizes scale with Icon Size.
- Drawn by Twofold, not composed from images, so every frame of the unfold is the same code path as the resting mark.
- Lit dots = the value in quarters, rounded, at least one when the value is above zero. Unlit dots are smaller and dim.
- Center shows a glyph for Wi-Fi, Bluetooth, Volume and Network, and the number for Battery, Memory, CPU and Disk.
- Accessibility description names each slot's reading, as the alternative does.

### 02 Unfold on click
- A click on the folded mark unfolds it; the motion copies the alternative frame for frame: the item widens to the left, the ring spins and straightens into a bar that becomes its icon, the center glyph grows and slides, the dots line up, bunch, and become their icon and value. About 370 ms with an ease-out, then a short settle.
- Unfolded, a click on an icon opens the popover at that module's page, under that icon. A click between icons opens the full list.
- It folds back, the exact reverse, when the popover closes, on a click anywhere else, or after 6 s without a click while the popover is closed.
- Settings → General → Click chooses Unfold into Icons (default) or Show Popover. Right-click always opens the full list.
- Reduce Motion replaces the morph with a crossfade.

### 03 Popover and pages
- A real `NSPopover` with its arrow and the system opening animation, 362 pt wide, rows as in the alternative, Settings… and Quit at the bottom.
- A page replaces the list with a crossfade (out ≈ 50 ms, in ≈ 80 ms) while the popover resizes. Back, `Esc` on a page, or the chevron returns to the list; `Esc` on the list closes.
- Values refresh every 2 s. The sample is a handful of syscalls; a slower idle rate would only make the graphs uneven.

### 04 Battery
- Level, charging state, power source, time remaining, Low Power Mode state (the row opens Battery settings, since changing it needs admin rights), maximum capacity and cycle count from `AppleSmartBattery`.
- Macs without a battery show "No battery" and the ring falls back to empty.

### 05 Wi-Fi
- The round well and the page header switch toggle Wi-Fi power through CoreWLAN.
- Network names need Location access, as in the alternative, with the same explanation and an Allow button. With access the page lists nearby networks with signal and lock.
- The ring value is signal quality from RSSI.

### 06 Bluetooth
- Paired devices with a glyph by device class and the connection state. Clicking a device connects or disconnects it.
- Battery levels only where macOS exposes them publicly (HID devices through IOKit). AirPods battery has no public API; leave it out rather than scrape.

### 07 Sound
- Volume slider in the row and on the page, mute on the speaker icon, output device picker, all through CoreAudio.

### 08 Display
- Keep Awake (a display-sleep assertion), each display's name, resolution, and refresh rate.

### 09 Network activity
- Rates from 64-bit interface counters, summed over physical interfaces, sampled every 2 s, with a one-minute history graph (download blue, upload orange).
- Connection kind and the primary IPv4 address.

### 10 Memory
- App, Wired, Compressed, and Cached split the way Activity Monitor computes them, with the stacked bar.

### 11 CPU
- User, system, idle from tick deltas, a one-minute graph, load averages, cores, thermal state, uptime.

### 12 Disk
- Every visible local volume with free space ("important usage" capacity) and a bar that turns red above 90%.

### 13 Live moments
- Charging started or stopped, battery low (20% and 10%), mute toggled, an output device change, a Bluetooth device connected, a drive mounted.
- The center glyph crossfades to the event's glyph, the ring may show the event's value, and a two-line label widens the item to the right of the mark for 2.5 s, then everything steps back. Moments never interrupt an unfold.
- On by default, Settings → General → Show moments.

### 14 Indicator settings
- Slots (8 metrics each), ring style (Solid, Gradient, Segmented) picked from drawings, thickness, icon size, and the nine colors with a live Now / Low / High preview.

### 15 Popover settings and profiles
- Row visibility and order (drag), Reset Order, Show details.
- Profiles save the three slots. "Add the three starters" adds Work, Travel, Minimal. With profiles, a segmented switcher sits at the top of the popover.

### 16 General settings
- Launch at login through `SMAppService`, Click action, Show moments.
