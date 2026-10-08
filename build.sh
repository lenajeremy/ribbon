#!/bin/zsh
# Builds Ribbon and installs it to /Applications, replacing (and relaunching) any running copy.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

STAGE=".build/Ribbon.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp .build/release/Ribbon "$STAGE/Contents/MacOS/Ribbon"

# App icon: the layered Icon Composer document becomes Assets.car (+ an .icns for older macOS).
xcrun actool Resources/AppIcon.icon --compile "$STAGE/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist .build/icon-info.plist >/dev/null

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.jeremiahlena.focusorb</string>
    <key>CFBundleName</key><string>Ribbon</string>
    <key>CFBundleDisplayName</key><string>Ribbon</string>
    <key>CFBundleExecutable</key><string>Ribbon</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>3.0</string>
    <key>CFBundleVersion</key><string>4</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Ribbon reads the address of the tab you're on to track which websites you use, and redirects blocked sites during focus sessions.</string>
    <key>RibbonEnvFile</key><string>$PWD/.env</string>
</dict>
</plist>
PLIST

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
