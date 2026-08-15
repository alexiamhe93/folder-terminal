#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Resources/Info.plist")"
ARCHIVE_PATH="$ROOT_DIR/dist/FolderTerminal-$VERSION-macOS.zip"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

cd "$ROOT_DIR"
./scripts/build-app.sh

rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
ditto -c -k --sequesterRsrc --keepParent \
    "$ROOT_DIR/dist/FolderTerminal.app" \
    "$ARCHIVE_PATH"

cd "$ROOT_DIR/dist"
shasum -a 256 "$(basename "$ARCHIVE_PATH")" > "$(basename "$CHECKSUM_PATH")"

echo "Packaged $ARCHIVE_PATH"
echo "Checksum $CHECKSUM_PATH"
