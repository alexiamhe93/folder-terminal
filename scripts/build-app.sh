#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FolderTerminal"
CONFIGURATION="${CONFIGURATION:-release}"
APP_PATH="${APP_PATH:-$ROOT_DIR/dist/$APP_NAME.app}"
INSTALL_APP=0

usage() {
    echo "Usage: scripts/build-app.sh [--install]"
    echo ""
    echo "Builds and ad-hoc signs dist/FolderTerminal.app."
    echo "--install also copies it to \${INSTALL_DIR:-$HOME/Applications}."
}

case "${1:-}" in
    "") ;;
    --install) INSTALL_APP=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
esac

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

# Some Command Line Tools updates briefly ship a default SDK that is newer than
# their Swift compiler. The retained 15.4 SDK still supports this app's macOS 14
# deployment target and provides a safe local fallback for that specific setup.
if [[ -z "${SDKROOT:-}" ]] \
    && [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]] \
    && [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi

typeset -a SWIFT_OPTIONS
SWIFT_OPTIONS=()
if [[ "${FOLDERTERMINAL_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
    SWIFT_OPTIONS+=(--disable-sandbox)
fi

# Build a native app by default. Release automation can request a universal
# binary with SWIFT_ARCHS="arm64 x86_64".
if [[ -n "${SWIFT_ARCHS:-}" ]]; then
    for architecture in ${(z)SWIFT_ARCHS}; do
        SWIFT_OPTIONS+=(--arch "$architecture")
    done
fi

cd "$ROOT_DIR"
echo "Building $APP_NAME ($CONFIGURATION)…"
if ! swift build "${SWIFT_OPTIONS[@]}" -c "$CONFIGURATION" --product "$APP_NAME"; then
    echo ""
    echo "Build failed. If Swift reports an SDK/compiler mismatch, install full Xcode or select a matching Xcode toolchain with xcode-select before retrying."
    exit 1
fi

BIN_PATH="$(swift build "${SWIFT_OPTIONS[@]}" -c "$CONFIGURATION" --show-bin-path)"
CONTENTS="$APP_PATH/Contents"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES"
cp "$BIN_PATH/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"

plutil -lint "$CONTENTS/Info.plist"
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "Built $APP_PATH"

if (( INSTALL_APP )); then
    INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    ditto "$APP_PATH" "$INSTALL_DIR/$APP_NAME.app"
    echo "Installed $INSTALL_DIR/$APP_NAME.app"
fi
