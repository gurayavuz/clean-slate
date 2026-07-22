#!/bin/bash
# Builds "Clean Slate.app" and installs it to /Applications.
#
#   ./build.sh                 release build, installed
#   ./build.sh debug           debug build, installed
#   ./build.sh --no-install    build only, bundle left in .build/
#
# The bundle is staged inside .build/ so /Applications holds the only copy you
# can see and click. A second identically-named app next to the source is a trap:
# it has no Full Disk Access grant, so launching it by mistake just finds less.
#
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
INSTALL=1
for arg in "$@"; do
    case "$arg" in
        debug|release) CONFIG="$arg" ;;
        --no-install)  INSTALL=0 ;;
        *) echo "usage: build.sh [debug|release] [--no-install]" >&2; exit 1 ;;
    esac
done

APP_NAME="Clean Slate.app"
APP=".build/$APP_NAME"
INSTALL_DIR="/Applications"
DEST="$INSTALL_DIR/$APP_NAME"

# Clear out the bundle earlier builds left beside the source.
rm -rf "./$APP_NAME"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/CleanSlate"

# Icon generation is slow-ish and rarely changes; regenerate only when missing.
[ -f Resources/AppIcon.icns ] || ./tools/make_icon.sh

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CleanSlate"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Clean Slate</string>
    <key>CFBundleDisplayName</key>       <string>Clean Slate</string>
    <key>CFBundleExecutable</key>        <string>CleanSlate</string>
    <key>CFBundleIdentifier</key>        <string>com.gurayavuz.cleanslate</string>
    <key>CFBundleVersion</key>           <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <!-- Menu bar only: no Dock icon, ever. Set here rather than at runtime so
         the icon never flashes into the Dock during launch. -->
    <key>LSUIElement</key>               <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# Finder leaves xattrs on the bundle that codesign rejects under --strict.
xattr -cr "$APP"

# Full Disk Access is keyed to the code signature. A stable identity gives the
# bundle a designated requirement that survives rebuilds, so the grant sticks;
# ad-hoc signing means re-granting after every build.
IDENTITY="${CODESIGN_IDENTITY:-Clean Slate Local Signing}"
if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "warning: no '$IDENTITY' identity found — signing ad-hoc." >&2
    echo "         Full Disk Access will need re-granting after each build." >&2
    codesign --force --deep --sign - "$APP"
fi

# Finder re-adds FinderInfo the moment the folder becomes a bundle; it isn't
# sealed by the signature, but it trips --strict verification if left behind.
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true

echo "Built $APP"

[ "$INSTALL" = 1 ] || exit 0

# /Applications is the copy that actually runs; the bundle above is only a
# staging area. Keeping one canonical location matters here because both the
# Full Disk Access grant and the login-item registration are tied to the app's
# path, and a second copy silently competes for them.
if [ ! -w "$INSTALL_DIR" ]; then
    echo "warning: $INSTALL_DIR isn't writable — skipping install." >&2
    echo "         Run: sudo ditto \"$PWD/$APP\" \"$DEST\"" >&2
    exit 0
fi

# Was the installed copy set to open at login? Re-register afterwards so the
# setting points at the new bundle rather than the one just replaced.
WAS_LOGIN_ITEM=0
if [ -x "$DEST/Contents/MacOS/CleanSlate" ] &&
   "$DEST/Contents/MacOS/CleanSlate" --login-item status 2>/dev/null | grep -q enabled; then
    WAS_LOGIN_ITEM=1
fi

# Replacing a bundle under a live process gives you a half-updated app.
pkill -f "$APP_NAME/Contents/MacOS/CleanSlate" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
ditto "$APP" "$DEST"
xattr -d com.apple.FinderInfo "$DEST" 2>/dev/null || true
echo "Installed $DEST"

if [ "$WAS_LOGIN_ITEM" = 1 ]; then
    "$DEST/Contents/MacOS/CleanSlate" --login-item on >/dev/null 2>&1 \
        && echo "Re-registered login item" \
        || echo "warning: could not re-register login item — toggle it in the menu." >&2
fi
