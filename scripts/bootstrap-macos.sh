#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

require_command() {
    command_name=$1
    install_hint=$2
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'Missing required command: %s\n%s\n' "$command_name" "$install_hint" >&2
        exit 1
    fi
}

require_command xcodebuild "Install full Xcode from the App Store, open it once, and finish installing the iOS platform."
require_command node "Install current Node.js LTS (Homebrew: brew install node)."
require_command npm "Install current Node.js LTS (Homebrew: brew install node)."
require_command xcodegen "Install XcodeGen (Homebrew: brew install xcodegen)."

developer_dir=${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}
case "$developer_dir" in
    */Xcode.app/Contents/Developer)
        ;;
    *)
        if [ -d /Applications/Xcode.app/Contents/Developer ]; then
            developer_dir=/Applications/Xcode.app/Contents/Developer
        else
            printf '%s\n' "Full Xcode was not found in /Applications." >&2
            printf '%s\n' "Install and open Xcode once, then rerun make bootstrap." >&2
            exit 1
        fi
        ;;
esac
export DEVELOPER_DIR=$developer_dir
xcodebuild -version >/dev/null

printf '%s\n' "Installing relay development dependencies..."
(cd "$REPOSITORY_DIR/relay" && npm ci)

printf '%s\n' "Downloading and verifying the sherpa-onnx iOS runtime and Mandarin model..."
"$REPOSITORY_DIR/scripts/fetch-sherpa-onnx-ios.sh"

printf '%s\n' "Generating the Xcode project..."
(cd "$REPOSITORY_DIR/ios" && xcodegen generate)

printf '%s\n' "Running repository checks..."
(cd "$REPOSITORY_DIR" && make check)

printf '\n%s\n' "Bootstrap complete. Open ios/MandarinListener.xcodeproj in Xcode."
