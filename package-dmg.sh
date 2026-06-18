#!/bin/bash
# Build a release ImageOptimizer.app and package it into a distributable .dmg.
# Note: ad-hoc signed only (no Apple Developer ID / notarization), so a downloaded
# copy triggers a one-time Gatekeeper prompt on first launch.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP="ImageOptimizer.app"
DMG="StudioVybeImageOptimizer.dmg"
VOLNAME="Studio Vybe Image Optimizer"

echo "Building release..."
swift build -c release

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp .build/release/ImageOptimizer "$APP/Contents/MacOS/ImageOptimizer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Fonts/*.otf "$APP/Contents/Resources/Fonts/" 2>/dev/null || true
codesign --force --deep --sign - "$APP"

echo "Creating $DMG..."
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "Done: $DMG ($(du -h "$DMG" | cut -f1))"
