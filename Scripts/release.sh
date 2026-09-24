#!/bin/bash
# Builds a distributable DMG of Sorla in .build/release-artifacts.
#
#   Scripts/release.sh                    build, sign and verify the DMG
#   SORLA_NOTARIZE=1 Scripts/release.sh   also notarize and staple it
#                                         (only with a Developer ID identity)
#
# Notarizing reads the App Store Connect API key details from the environment
# or from a local file outside the repository (see Scripts/release.env.example):
#   ${SORLA_RELEASE_CONFIG:-~/.config/sorla/release.env}
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR=".build/Sorla.app"
ARTIFACTS_DIR=".build/release-artifacts"
RELEASE_CONFIG="${SORLA_RELEASE_CONFIG:-$HOME/.config/sorla/release.env}"
if [ -f "$RELEASE_CONFIG" ]; then
    # shellcheck source=/dev/null
    source "$RELEASE_CONFIG"
fi

# 1. Pick a signing identity: Developer ID if there is one, otherwise Apple Development.
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
IDENTITY="$(echo "$IDENTITIES" | awk '/"Developer ID Application/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
    DEVELOPER_ID=1
else
    DEVELOPER_ID=0
    IDENTITY="$(echo "$IDENTITIES" | awk '/"Apple Development/ {print $2; exit}')"
    echo "warning: no Developer ID Application identity in the keychain." >&2
    echo "warning: signing with Apple Development; the DMG will not open cleanly on other Macs." >&2
fi
if [ -z "$IDENTITY" ]; then
    echo "error: no Developer ID Application or Apple Development identity found." >&2
    exit 1
fi
echo "Signing identity: $(echo "$IDENTITIES" | grep "$IDENTITY" | head -1 | sed 's/^ *[0-9]*) //')"

SORLA_SIGN_IDENTITY="$IDENTITY" Scripts/build-app.sh

# 2. Verify the app.
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "Gatekeeper assessment (informational):"
spctl -a -vv "$APP_DIR" || true

# 3. Build and sign the DMG.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
DMG_PATH="$ARTIFACTS_DIR/Sorla-$VERSION.dmg"
STAGING_DIR="$ARTIFACTS_DIR/dmg-staging"

mkdir -p "$ARTIFACTS_DIR"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/Sorla.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "Sorla" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"
rm -rf "$STAGING_DIR"

codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

# 4. Notarize (Developer ID and SORLA_NOTARIZE=1 only).
# The API key is only passed by path; the script never reads it.
if [ "${SORLA_NOTARIZE:-0}" = "1" ]; then
    if [ "$DEVELOPER_ID" = "1" ]; then
        for name in ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID; do
            if [ -z "${!name:-}" ]; then
                echo "error: $name is not set; add it to $RELEASE_CONFIG (see Scripts/release.env.example)." >&2
                exit 1
            fi
        done
        xcrun notarytool submit "$DMG_PATH" \
            --key "$ASC_KEY_PATH" \
            --key-id "$ASC_KEY_ID" \
            --issuer "$ASC_ISSUER_ID" \
            --wait
        xcrun stapler staple "$DMG_PATH"
    else
        echo "warning: SORLA_NOTARIZE=1 but not signed with Developer ID; skipping notarization." >&2
    fi
fi

# 5. Report.
echo
echo "DMG:     $DMG_PATH"
echo "Size:    $(du -h "$DMG_PATH" | cut -f1)"
echo "SHA-256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
echo "After the GitHub release is published, run Scripts/update-cask.sh to update the Homebrew cask."
