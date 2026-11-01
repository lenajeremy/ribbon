# Ribbon for iPhone

The iPhone version of Ribbon: focus sessions that block apps and websites, schedules, session reviews, and your day from Screen Time.

## Build

```sh
cd iOS
xcodegen                 # makes Ribbon.xcodeproj from project.yml
open Ribbon.xcodeproj    # run the Ribbon scheme
```

Blocking and Screen Time only work on a real iPhone. To install on a registered iPhone without signing Xcode in, build with the "Ribbon Dev" profiles: `xcodebuild -scheme Ribbon -xcconfig Signing/Dev.xcconfig -destination 'id=<UDID>' build`, then `xcrun devicectl device install app`. In the Simulator, launch with `-RibbonDemo` to fill the screens with sample data; `-RibbonTab focus|week` and `-RibbonOpen session|start|editor|schedule|review|settings` open a screen.

TestFlight and the App Store need Apple to approve the Family Controls (distribution) capability for the app and its extensions.

## Layout

```
Ribbon/                  the app: screens, session reviews
Shared/                  shared with the extensions: theme, models, storage, Engine (sessions and blocking)
Usage/                   the Today and This week views, drawn from Screen Time
ReportExtension/         draws Screen Time; iOS seals it off from the rest of Ribbon
MonitorExtension/        starts and ends sessions and counts distracting time while Ribbon is closed
ShieldExtension/         the blocked screen
ShieldActionExtension/   the blocked screen's Close button
Widgets/                 the session on the Lock Screen and in the Dynamic Island
```
