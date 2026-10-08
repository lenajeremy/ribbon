#!/bin/zsh
# Builds Ribbon and installs it to /Applications, replacing (and relaunching) any running copy.
# For a notarized DMG to share, use scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")"
source scripts/make_bundle.sh

swift build -c release
STAGE=".build/Ribbon.app"
make_bundle .build/release/Ribbon "$STAGE" "$PWD/.env"

# A stable signature keeps the Screen Recording permission across rebuilds.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --sign "${IDENTITY:--}" "$STAGE"

APP="/Applications/Ribbon.app"
pkill -x Ribbon && sleep 1 || true
# Ribbon used to be called Focus Orb; replace the old copy.
pkill -x FocusOrb && sleep 1 || true
if [[ -d "/Applications/Focus Orb.app" ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/Applications/Focus Orb.app" || true
    rm -rf "/Applications/Focus Orb.app"
fi
rm -rf "$APP"
ditto "$STAGE" "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
open "$APP"
echo "Installed and launched $APP (signed with ${IDENTITY:-ad-hoc})"
