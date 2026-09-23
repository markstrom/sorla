#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP_NAME="Sorla.app"
APP_DIR=".build/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/Sorla "$APP_DIR/Contents/MacOS/Sorla"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R Resources/Licenses "$APP_DIR/Contents/Resources/Licenses"
cp -R Resources/*.lproj "$APP_DIR/Contents/Resources/"

shopt -s nullglob
for bundle in .build/release/*.bundle; do
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
shopt -u nullglob

IDENTITY="${SORLA_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}' || true)}"
IDENTITY="${IDENTITY:--}"

# Secure timestamps need a real identity; ad-hoc ("-") signatures can't have one.
TIMESTAMP_FLAG=""
if [ "$IDENTITY" != "-" ]; then
    TIMESTAMP_FLAG="--timestamp"
fi

# The SwiftPM bundles copied into Resources hold only resources (no code), so they
# are signed on their own first, inside out, instead of using --deep on the app.
shopt -s nullglob
for bundle in "$APP_DIR"/Contents/Resources/*.bundle; do
    codesign --force --sign "$IDENTITY" $TIMESTAMP_FLAG "$bundle"
done
shopt -u nullglob

# Hardened runtime (required for notarization). The entitlements keep the
# microphone working under it.
codesign --force --sign "$IDENTITY" \
    --options runtime \
    --entitlements Resources/Sorla.entitlements \
    $TIMESTAMP_FLAG \
    "$APP_DIR"

echo "Built $APP_DIR (signed with: $IDENTITY)"
