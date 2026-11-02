#!/usr/bin/env bash
# Regenerates every platform launcher icon from assets/branding/*.svg.
#
# Uses only what ships with macOS: swift + AppKit does the rasterizing, because
# AppKit is the only decoder on the machine that reads SVG (ImageIO has no SVG
# type at all) and because sips always writes an alpha channel, which the iOS
# AppIcon set is not allowed to have.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SRC=assets/branding
RAST=(swift scripts/rasterize-svg.swift)

command -v swift >/dev/null || { echo "swift not found — install the Xcode command line tools" >&2; exit 1; }

# --- iOS ------------------------------------------------------------------
# Sizes are the pixel sizes the asset catalog's Contents.json declares.
IOS=ios/Runner/Assets.xcassets/AppIcon.appiconset
"${RAST[@]}" "$SRC/app_icon.svg" opaque \
  "$IOS/Icon-App-20x20@1x.png:20"      "$IOS/Icon-App-20x20@2x.png:40" \
  "$IOS/Icon-App-20x20@3x.png:60"      "$IOS/Icon-App-29x29@1x.png:29" \
  "$IOS/Icon-App-29x29@2x.png:58"      "$IOS/Icon-App-29x29@3x.png:87" \
  "$IOS/Icon-App-40x40@1x.png:40"      "$IOS/Icon-App-40x40@2x.png:80" \
  "$IOS/Icon-App-40x40@3x.png:120"     "$IOS/Icon-App-60x60@2x.png:120" \
  "$IOS/Icon-App-60x60@3x.png:180"     "$IOS/Icon-App-76x76@1x.png:76" \
  "$IOS/Icon-App-76x76@2x.png:152"     "$IOS/Icon-App-83.5x83.5@2x.png:167" \
  "$IOS/Icon-App-1024x1024@1x.png:1024"
echo "ios      $(ls "$IOS"/*.png | wc -l | tr -d ' ') icons"

# --- Android --------------------------------------------------------------
# Legacy square icon at 48dp, plus the two adaptive layers at 108dp for
# launchers that mask the icon to their own shape.
RES=android/app/src/main/res
legacy=(); fg=(); bg=()
# density:launcher-px(48dp):adaptive-layer-px(108dp)
for spec in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  IFS=: read -r d small large <<<"$spec"
  legacy+=("$RES/mipmap-$d/ic_launcher.png:$small")
  fg+=("$RES/mipmap-$d/ic_launcher_foreground.png:$large")
  bg+=("$RES/mipmap-$d/ic_launcher_background.png:$large")
done
"${RAST[@]}" "$SRC/app_icon.svg"            opaque "${legacy[@]}"
"${RAST[@]}" "$SRC/app_icon_foreground.svg" alpha  "${fg[@]}"
"${RAST[@]}" "$SRC/app_icon_background.svg" opaque "${bg[@]}"
echo "android  legacy + adaptive across 5 densities"

# --- Web ------------------------------------------------------------------
# The maskable icons are the same full-bleed artwork: the mark already sits
# inside the 80% safe circle a maskable icon has to survive.
"${RAST[@]}" "$SRC/app_icon.svg" alpha \
  "web/favicon.png:16" \
  "web/icons/Icon-192.png:192"          "web/icons/Icon-512.png:512" \
  "web/icons/Icon-maskable-192.png:192" "web/icons/Icon-maskable-512.png:512"
echo "web      favicon + 4 icons"

# --- Launch screens -------------------------------------------------------
# Drawn by the OS before any Dart runs, so the mark has to be a real image
# rather than a Flutter widget. 120pt on both platforms, which is the size the
# iOS storyboard's centred image view and the Android layer-list expect.
IOSLAUNCH=ios/Runner/Assets.xcassets/LaunchImage.imageset
"${RAST[@]}" "$SRC/logo_mark.svg" alpha \
  "$IOSLAUNCH/LaunchImage.png:120" \
  "$IOSLAUNCH/LaunchImage@2x.png:240" \
  "$IOSLAUNCH/LaunchImage@3x.png:360"
launch=()
for spec in mdpi:120 hdpi:180 xhdpi:240 xxhdpi:360 xxxhdpi:480; do
  IFS=: read -r d px <<<"$spec"
  launch+=("$RES/mipmap-$d/launch_image.png:$px")
done
"${RAST[@]}" "$SRC/logo_mark.svg" alpha "${launch[@]}"
echo "launch   iOS 1x/2x/3x + Android across 5 densities"
