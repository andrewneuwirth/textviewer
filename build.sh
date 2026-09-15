#!/bin/zsh
# Builds Readout.app (with its Quick Look extension) and installs it.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Readout"
EXT_NAME="ReadoutQuickLook"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
APPEX="$APP/Contents/PlugIns/$EXT_NAME.appex"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/$APP_NAME.icns" "$APP/Contents/Resources/$APP_NAME.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# The Quick Look extension shares the app's parser and tree rendering, but is a
# separate binary with its own entry point, so swiftc builds it directly.
mkdir -p "$APPEX/Contents/MacOS"
swiftc -O -module-name "$EXT_NAME" \
    Sources/Readout/JSONParser.swift \
    Sources/Readout/Theme.swift \
    Sources/Readout/TreeView.swift \
    Sources/QuickLook/PreviewViewController.swift \
    Sources/QuickLook/main.swift \
    -framework QuickLookUI \
    -o "$APPEX/Contents/MacOS/$EXT_NAME"
cp "Resources/QuickLook/Info.plist" "$APPEX/Contents/Info.plist"

# Nested code signs first, and the extension needs the sandbox entitlement
# before PlugInKit will load it.
codesign --force --sign - --timestamp=none \
    --entitlements "Resources/QuickLook/QuickLook.entitlements" "$APPEX"
codesign --force --sign - --timestamp=none "$APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "/Applications/$APP_NAME.app"
    pluginkit -a "/Applications/$APP_NAME.app/Contents/PlugIns/$EXT_NAME.appex" 2>/dev/null || true
    echo "installed to /Applications/$APP_NAME.app"
else
    echo "built $APP"
fi
