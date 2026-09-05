#!/bin/sh
# Assembles nootch.app from the release build and wraps it in an install DMG.
# Usage: packaging/build-app.sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/packaging/Info.plist")"
APP_NAME="nootch"
DIST="$ROOT/dist"
STAGE="$DIST/dmgroot"

swift build -c release --package-path "$ROOT"

rm -rf "$DIST"
mkdir -p "$STAGE" "$DIST/$APP_NAME.app/Contents/MacOS" "$DIST/$APP_NAME.app/Contents/Resources"

cp "$ROOT/.build/release/$APP_NAME" "$DIST/$APP_NAME.app/Contents/MacOS/"
cp "$ROOT/packaging/Info.plist" "$DIST/$APP_NAME.app/Contents/"
cp "$ROOT/Sources/Nootch/Resources/Nootch.icns" "$DIST/$APP_NAME.app/Contents/Resources/"
if [ -d "$ROOT/.build/release/${APP_NAME}_Nootch.bundle" ]; then
    cp -R "$ROOT/.build/release/${APP_NAME}_Nootch.bundle" "$DIST/$APP_NAME.app/Contents/Resources/"
fi

# Ad-hoc sign so Gatekeeper treats the bundle like the previous release.
codesign --force --deep --sign - "$DIST/$APP_NAME.app"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$DIST/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "nootch" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME-$VERSION.dmg"

echo "Built $DIST/$APP_NAME-$VERSION.dmg"
