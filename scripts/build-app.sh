#!/bin/bash
# Builds dist/Twofold.app (release, ad-hoc signed). Pass --run to relaunch it.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)/Twofold"

app=dist/Twofold.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Twofold"
cp Resources/Info.plist "$app/Contents/Info.plist"

# The icon is drawn by the app itself.
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
"$bin" --render-icon "$iconset/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app"
echo "Built $app"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x Twofold || true
  open "$app"
fi
