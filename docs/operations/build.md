# Build and check

- `swift build` compiles a debug binary. There is no Xcode project; the Command Line Tools are enough.
- `scripts/build-app.sh` builds a release binary and wraps it in `dist/Twofold.app` with `Resources/Info.plist`, an icon the binary draws itself (`--render-icon`), and an ad-hoc signature. `--run` relaunches it.
- The Command Line Tools ship without SwiftUI's macro plugins, so SwiftUI macros such as `@State`, `@Entry` and `#Preview` don't compile. Use `@StateObject`, `@Bindable`, or plain properties. Observation's `@Observable` works.

## Checking motion

`Twofold --render-unfold <dir>` writes one PNG per 60 fps frame of the unfold and a resting mark per ring style. Tile them to compare with the strips in `docs/feature-reference/02-unfold/`:

```sh
.build/debug/Twofold --render-unfold /tmp/unfold
ffmpeg -framerate 1 -i /tmp/unfold/unfold-%03d.png -vf tile=4x8 /tmp/unfold.png
```

For the real menu bar, record with `ffmpeg -f avfoundation -framerate 60 -capture_cursor 0 -i "<screen>:none"` and crop to the item.

## Permissions while testing

A binary started from a terminal borrows the terminal's Bluetooth and Location permissions. The app bundle asks for its own, so test permission flows with `open dist/Twofold.app`.
