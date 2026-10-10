# Assembles Ribbon.app around a built executable. Sourced by build.sh and scripts/release.sh.
# Usage: make_bundle <executable> <app path> [.env file to read the API key from]
RIBBON_VERSION="${RIBBON_VERSION:-3.8}"
RIBBON_BUILD="${RIBBON_BUILD:-12}"

make_bundle() {
    local executable="$1" app="$2" env_file="${3:-}"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$executable" "$app/Contents/MacOS/Ribbon"

    # The layered Icon Composer document becomes Assets.car (+ an .icns for older macOS).
    xcrun actool Resources/AppIcon.icon --compile "$app/Contents/Resources" \
        --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist .build/icon-info.plist >/dev/null

    local env_entry=""
    [[ -n "$env_file" ]] && env_entry="    <key>RibbonEnvFile</key><string>$env_file</string>"
    cat > "$app/Contents/Info.plist" <<PLIST
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
    <key>CFBundleShortVersionString</key><string>$RIBBON_VERSION</string>
    <key>CFBundleVersion</key><string>$RIBBON_BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>NSAppleEventsUsageDescription</key><string>Ribbon reads the address of the tab you're on to track which websites you use, and redirects blocked sites during focus sessions.</string>
$env_entry
</dict>
</plist>
PLIST
}
