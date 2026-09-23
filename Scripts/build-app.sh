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
cp -R Resources/Licenses "$APP_DIR/Contents/Resources/Licenses"

shopt -s nullglob
for bundle in .build/release/*.bundle; do
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
shopt -u nullglob

IDENTITY="${SORLA_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}' || true)}"
IDENTITY="${IDENTITY:--}"
codesign --force --deep --sign "$IDENTITY" "$APP_DIR"

echo "Built $APP_DIR (signed with: $IDENTITY)"
