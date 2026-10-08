#!/bin/zsh
# Builds a universal, signed and notarized Ribbon.dmg in dist/.
# Needs a "Developer ID Application" certificate and notarytool credentials saved once:
#   xcrun notarytool store-credentials ribbon-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
# Set NOTARY_PROFILE to use a different profile name, or SKIP_NOTARIZE=1 to stop after signing.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/make_bundle.sh

PROFILE="${NOTARY_PROFILE:-ribbon-notary}"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}"
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate in your keychain." >&2; exit 1; }

notarize() {
    local output
    output=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1) || true
    echo "$output"
    [[ "$output" == *"status: Accepted"* ]] || { echo "Notarization of $1 failed." >&2; exit 1; }
}

echo "Building for Apple silicon and Intel…"
swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
rm -rf dist && mkdir -p dist
make_bundle "$BIN/Ribbon" dist/Ribbon.app
codesign --force --options runtime --timestamp --entitlements Resources/Ribbon.entitlements --sign "$IDENTITY" dist/Ribbon.app
codesign --verify --strict --verbose=1 dist/Ribbon.app

if [[ "${SKIP_NOTARIZE:-}" != "1" ]]; then
    echo "Notarizing the app…"
    ditto -c -k --keepParent dist/Ribbon.app dist/Ribbon.zip
    notarize dist/Ribbon.zip
    xcrun stapler staple dist/Ribbon.app
fi
# Ribbon.zip is what the in-app updater downloads, so zip the app again now that it's stapled.
rm -f dist/Ribbon.zip
ditto -c -k --keepParent dist/Ribbon.app dist/Ribbon.zip

echo "Making the disk image…"
mkdir -p dist/dmg
cp -R dist/Ribbon.app dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "Ribbon" -srcfolder dist/dmg -ov -format UDZO -quiet dist/Ribbon.dmg
rm -rf dist/dmg
codesign --force --timestamp --sign "$IDENTITY" dist/Ribbon.dmg

if [[ "${SKIP_NOTARIZE:-}" != "1" ]]; then
    echo "Notarizing the disk image…"
    notarize dist/Ribbon.dmg
    xcrun stapler staple dist/Ribbon.dmg
    spctl --assess --type open --context context:primary-signature --verbose=1 dist/Ribbon.dmg
fi
echo "Done: dist/Ribbon.dmg and dist/Ribbon.zip (Ribbon $RIBBON_VERSION). Publish them with scripts/publish.sh."
