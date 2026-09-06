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
# The resource bundle is not optional: without it every logo and the app icon
# silently disappear. Fail here rather than shipping a DMG that is missing them.
BUNDLE="$ROOT/.build/release/${APP_NAME}_Nootch.bundle"
if [ ! -d "$BUNDLE" ]; then
    echo "error: $BUNDLE not found; cannot package without resources" >&2
    exit 1
fi
# Keep resources under Contents/Resources. Placing the bundle at the app root to
# satisfy SwiftPM's Bundle.module would leave unsealed contents there, which
# invalidates the signature and stops Keychain "Always Allow" from ever
# sticking. ResourceBundle.swift looks here instead.
cp -R "$BUNDLE" "$DIST/$APP_NAME.app/Contents/Resources/"

# Sign with a real Developer ID when one is available, so the app has a stable
# code signing identity across releases. Keychain ACL entries are keyed on that
# identity; an ad-hoc signature falls back to the binary's cdhash, which changes
# on every build and silently voids any previous "Always Allow" grant.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    # Ad-hoc, as before. The hardened runtime is skipped here because it only
    # buys anything alongside notarization, which needs a real identity.
    codesign --force --deep --sign - "$DIST/$APP_NAME.app"
else
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$DIST/$APP_NAME.app"
fi
# A bundle that fails verification has no usable code requirement, so Keychain
# prompts return on every read. Catch that here instead of in the wild.
codesign --verify --strict --verbose=2 "$DIST/$APP_NAME.app"

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$DIST/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "nootch" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME-$VERSION.dmg"

echo "Built $DIST/$APP_NAME-$VERSION.dmg"
