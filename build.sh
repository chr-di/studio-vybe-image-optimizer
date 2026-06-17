#!/bin/bash
# Build Image Optimizer and create .app bundle.
#   bash build.sh           — build + bundle
#   bash build.sh --icon    — also regenerate AppIcon.icns from the Studio Vybe logo
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Studio Vybe brand mark used for the app icon (cream monogram on warm-dark squircle).
ICON_SVG="Resources/icon/icon-logo-svybe-negative.svg"
ICON_LOGO_FRACTION="0.62"

if [ "$1" == "--icon" ]; then
	if [ -f "$ICON_SVG" ]; then
		echo "Generating app icon from $ICON_SVG ..."
		swift scripts/make-appicon.swift "$ICON_SVG" "Resources/AppIcon.iconset" "$ICON_LOGO_FRACTION"
		iconutil -c icns "Resources/AppIcon.iconset" -o "Resources/AppIcon.icns"
		rm -rf "Resources/AppIcon.iconset" "Resources/icon-preview-256.png"
	else
		echo "Skipping icon regen — brand SVG not present ($ICON_SVG)."
		echo "Resources/icon/ is gitignored; using the committed Resources/AppIcon.icns."
	fi
fi

echo "Building..."
swift build

echo "Creating app bundle..."
APP_DIR="$SCRIPT_DIR/ImageOptimizer.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/debug/ImageOptimizer "$APP_DIR/Contents/MacOS/ImageOptimizer"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Bundle the Inter font faces (registered at launch by FontLoader; ATSApplicationFontsPath
# in Info.plist lets the system register them too as a backstop).
mkdir -p "$APP_DIR/Contents/Resources/Fonts"
cp Resources/Fonts/*.otf "$APP_DIR/Contents/Resources/Fonts/" 2>/dev/null || true

# Ad-hoc sign so security-scoped bookmarks work (persists folder access)
codesign --force --sign - "$APP_DIR"

echo "Done: $APP_DIR"
echo "Run: open $APP_DIR"
