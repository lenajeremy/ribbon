# Ribbon

The AI time tracker for Mac. Ribbon records the apps and websites you use, shows where your day went, and blocks distractions when you need to focus.

**Website:** https://lenajeremy.github.io/ribbon/

![Ribbon's Today view](docs/screenshot.png)

## What it does

- **Tracks itself.** Every app and website, timed to the second, with idle and lock-screen detection. Everything is stored locally.
- **Sorts your time with AI.** Apps and sites land in categories on their own (OpenAI's Decisions API). Add your own categories by describing what belongs in them.
- **Shows your day.** A daily ribbon of your activity, focus blocks, breaks, Productivity / Focus / Break scores, and daily and weekly reviews written by AI.
- **Focus sessions.** Session types decide which apps and websites you can use. Anything else is hidden or quit, and blocked tabs turn into a "blocked" page. An optional orb watches your screens and nudges you out loud when you drift.
- **Ask your day.** Ask questions like "Where did my afternoon go?" and get answers from your own log.

## Requirements

- macOS 14 or later, Apple silicon or Intel
- Xcode with Swift 6 (command line tools are enough to build)
- An OpenAI API key (models: `gpt-6-luna` for sorting, reviews and answers; `gpt-4o-mini-tts` for the orb's voice)

## Build and run

```sh
git clone https://github.com/lenajeremy/ribbon.git
cd ribbon
cp .env.example .env      # then put your OpenAI API key in .env
./build.sh                # builds, installs to /Applications/Ribbon.app and launches it
```

Ribbon lives in the menu bar. Open the dashboard from there, or open Ribbon again from Spotlight.

`build.sh` signs with your Apple Development certificate if you have one, so macOS remembers the permissions below across rebuilds; otherwise it signs ad hoc.

## Permissions

| Permission | What it's for |
|---|---|
| Screen Recording | Reading window titles, and the orb's screen checks during focus sessions |
| Automation (per browser) | Reading the current tab's address in Chrome, Safari, Arc, Brave and Edge, and redirecting blocked sites |
| Accessibility | Hiding apps a focus session doesn't allow (without it, they're quit) |
| Notifications | Break reminders and "session done" alerts |

## Privacy

Your timeline, sessions, chats and settings are stored on your Mac in `~/Library/Application Support/Ribbon`. The AI sees app names, website names, page titles and totals. Screenshots are only taken during focus sessions that watch your screen, are sent to OpenAI to judge whether you're on task, and are never saved.

## Project layout

```
Sources/Ribbon/
  App/         launch, settings, menu bar
  Tracking/    activity tracker, browser access, break reminders
  AI/          OpenAI client, categorizer, reviews and answers
  Data/        local database, categories, scores
  Focus/       focus sessions, blocking, the orb
  Dashboard/   the dashboard window
Resources/AppIcon.icon   the app icon (Icon Composer); redraw it with `swift scripts/make_icon.swift`
docs/                    the website
```

## License

MIT
