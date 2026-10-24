#!/bin/bash
# Builds dist/KIndicator-<version>.dmg: a universal app signed with Developer ID,
# notarized and stapled, inside a signed, notarized and stapled disk image.
#
# Needs a "Developer ID Application" certificate in the keychain and notarization
# credentials saved once with:
#   xcrun notarytool store-credentials kindicator-notary --apple-id <id> --team-id <team>
#
# For a trial run without those: SIGN_IDENTITY="Apple Development" ./release.sh --skip-notarize
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="KIndicator"
EXECUTABLE="KIndicator"
NOTARY_PROFILE="${NOTARY_PROFILE:-kindicator-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
NOTARIZE=true
[[ "${1:-}" == "--skip-notarize" ]] && NOTARIZE=false

IDENTITY_PATTERN="${SIGN_IDENTITY:-Developer ID Application}"
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' -v p="$IDENTITY_PATTERN" 'index($2, p) { print $2; exit }')
if [[ -z "$IDENTITY" ]]; then
    echo "No signing identity matching \"$IDENTITY_PATTERN\" in the keychain." >&2
    exit 1
fi

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

echo "==> Building $APP_NAME $VERSION (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"

echo "==> Signing with $IDENTITY"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if $NOTARIZE; then
    # Notarize and staple the app itself, so it also opens offline once copied out of the image.
    echo "==> Notarizing the app"
    ZIP="$DIST/$APP_NAME.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    xcrun stapler staple "$APP"
    rm "$ZIP"
fi

echo "==> Creating $DMG"
STAGING=$(mktemp -d)
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if $NOTARIZE; then
    echo "==> Notarizing the disk image"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    spctl --assess --type execute --verbose=2 "$APP"
fi

echo "==> Done: $DMG"
