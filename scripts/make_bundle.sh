# Assembles Ribbon.app around a built executable. Sourced by build.sh and scripts/release.sh.
# Usage: make_bundle <executable> <app path> [.env file to read the API key from]
RIBBON_VERSION="${RIBBON_VERSION:-3.20}"
RIBBON_BUILD="${RIBBON_BUILD:-24}"

make_bundle() {
    local executable="$1" app="$2" env_file="${3:-}"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$executable" "$app/Contents/MacOS/Ribbon"

    # The layered Icon Composer document becomes Assets.car (+ an .icns for older macOS).
    xcrun actool Resources/AppIcon.icon --compile "$app/Contents/Resources" \
        --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist .build/icon-info.plist >/dev/null

    # Reopens Ribbon within a minute if it's quit during a scheduled focus session (registered by the app while
    # a schedule is on). It reads the windows Ribbon writes to "scheduled-windows", one "start end" pair per line.
    mkdir -p "$app/Contents/Library/LaunchAgents"
    cat > "$app/Contents/Library/LaunchAgents/com.jeremiahlena.focusorb.keepopen.plist" <<'AGENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.jeremiahlena.focusorb.keepopen</string>
    <key>AssociatedBundleIdentifiers</key><array><string>com.jeremiahlena.focusorb</string></array>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>f="$HOME/Library/Application Support/Ribbon/scheduled-windows"; [ -f "$f" ] || exit 0; now=$(date +%s); while read -r start end; do if [ "$now" -ge "$start" ] &amp;&amp; [ "$now" -lt "$end" ]; then pgrep -x Ribbon &gt;/dev/null || open -g -b com.jeremiahlena.focusorb; exit 0; fi; done &lt; "$f"</string>
    </array>
    <key>StartInterval</key><integer>60</integer>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
AGENT

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
