#!/bin/bash
# Builds "KIndicator.app". Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="KIndicator"
EXECUTABLE="KIndicator"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
APP=".build/app/$APP_NAME.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"

# A stable signing identity keeps the login item valid across rebuilds; fall back to ad-hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$EXECUTABLE" 2>/dev/null && sleep 0.5 || true
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    ditto "$APP" "$INSTALL_DIR/$APP_NAME.app"
    open "$INSTALL_DIR/$APP_NAME.app"
    echo "Installed to $INSTALL_DIR/$APP_NAME.app"
fi
