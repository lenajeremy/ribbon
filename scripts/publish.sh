#!/bin/zsh
# Publishes dist/Ribbon.dmg and dist/Ribbon.zip as a GitHub release, with this version's section of
# CHANGELOG.md as its notes. Run scripts/release.sh first. Copies of Ribbon update from these releases.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/make_bundle.sh

NOTES=$(awk -v version="$RIBBON_VERSION" '/^## / { if (found) exit; found = ($2 == version); next } found' CHANGELOG.md)
[[ -n "${NOTES//[[:space:]]/}" ]] || { echo "Add a \"## $RIBBON_VERSION\" section to CHANGELOG.md first." >&2; exit 1; }
BUILT=$(defaults read "$PWD/dist/Ribbon.app/Contents/Info" CFBundleShortVersionString)
[[ "$BUILT" == "$RIBBON_VERSION" ]] || { echo "dist/Ribbon.app is $BUILT, not $RIBBON_VERSION. Run scripts/release.sh first." >&2; exit 1; }
[[ -f dist/Ribbon.zip && -f dist/Ribbon.dmg ]] || { echo "dist/Ribbon.zip or dist/Ribbon.dmg is missing. Run scripts/release.sh first." >&2; exit 1; }

gh release create "v$RIBBON_VERSION" dist/Ribbon.dmg dist/Ribbon.zip --title "Ribbon $RIBBON_VERSION" --notes "$NOTES"
