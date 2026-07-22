#!/bin/bash
# Regenerates Resources/AppIcon.icns from tools/make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Resources
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swift tools/make_icon.swift "$TMP/icon.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size          "$TMP/icon.png" --out "$ICONSET/icon_${size}x${size}.png"       >/dev/null
    sips -z $((size*2)) $((size*2)) "$TMP/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp "$TMP/icon.png" Resources/icon-preview.png
echo "wrote Resources/AppIcon.icns"
