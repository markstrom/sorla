#!/bin/bash
# Points the Homebrew cask in markstrom/homebrew-tap at a published release.
# Run after the GitHub release exists: Scripts/update-cask.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)}"
DMG=".build/release-artifacts/Sorla-$VERSION.dmg"
URL="https://github.com/markstrom/sorla/releases/download/v$VERSION/Sorla-$VERSION.dmg"

# Hash the file people will actually download, so the cask can never disagree with the release.
SHA="$(curl --fail --silent --show-error --location "$URL" | shasum -a 256 | awk '{print $1}')"
if [ -f "$DMG" ]; then
    LOCAL_SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
    if [ "$LOCAL_SHA" != "$SHA" ]; then
        echo "error: the released DMG differs from $DMG" >&2
        exit 1
    fi
fi

TAP="$(mktemp -d)"
trap 'rm -rf "$TAP"' EXIT
git clone --quiet https://github.com/markstrom/homebrew-tap.git "$TAP"

CASK="$TAP/Casks/sorla.rb"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

if git -C "$TAP" diff --quiet; then
    echo "Cask already at $VERSION"
    exit 0
fi

git -C "$TAP" commit --quiet --all --message "Sorla $VERSION"
git -C "$TAP" push --quiet origin main
echo "Cask updated to $VERSION ($SHA)"
