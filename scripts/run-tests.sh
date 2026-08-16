#!/bin/zsh

# Runs the test suite, with or without a full Xcode installation.
#
# swift-testing ships as a framework rather than as part of the Swift runtime.
# A full Xcode puts it where the compiler and dyld already look, so `swift test`
# just works. With only the Command Line Tools installed it is present but
# unsearched, and the suite fails three different ways as you go: `no such
# module 'Testing'` at compile time, then a missing `Testing.framework` at load
# time, then a missing `lib_TestingInterop.dylib` that the framework itself
# needs. The flags below supply the search paths for all three.
#
# They are added only when a full Xcode is absent, so a machine that has one
# builds exactly as it did before.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

typeset -a TEST_OPTIONS
TEST_OPTIONS=()

DEVELOPER_DIR_PATH="$(xcode-select -p)"
if [[ "$DEVELOPER_DIR_PATH" == "/Library/Developer/CommandLineTools" ]]; then
    FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
    INTEROP_LIB="$DEVELOPER_DIR_PATH/Library/Developer/usr/lib"

    if [[ ! -d "$FRAMEWORKS/Testing.framework" ]]; then
        echo "swift-testing was not found at $FRAMEWORKS."
        echo "Update the Command Line Tools (xcode-select --install) or install Xcode."
        exit 1
    fi

    TEST_OPTIONS+=(
        -Xswiftc -F -Xswiftc "$FRAMEWORKS"
        -Xlinker -F -Xlinker "$FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$INTEROP_LIB"
    )
fi

exec swift test "${TEST_OPTIONS[@]}" "$@"
