# Changelog

Ribbon shows the section for a new version when it offers you the update.

## 3.6

- **Session reviews.** When a focus session ends, Ribbon compares what you did with what you said you'd work on, and scores the session out of 100. Time on unrelated things, like YouTube during interview prep, and time away from your Mac come off the score. Time you paused doesn't count. The score appears next to the orb and in a notification, and the full review, with what counted, the points taken off and a tip, is under Focus sessions › Recent sessions.

## 3.5

- Fixed: on days you were active until midnight, the day's ribbon showed only four hours and cut off the evening. It now runs to midnight.
- Fixed: a few seconds of activity just after midnight no longer stretch the next day's ribbon back to midnight. It starts at your first real activity.

## 3.4

- **Check-ins.** Every 30 minutes, Ribbon looks at your day and sends a notification. If you've drifted to things like YouTube, it nudges you back, naming what pulled you away and what you're working toward. If it's going well, or you're turning a slow day around, it encourages you, at most once an hour. It stays quiet during focus sessions and while you're away. Turn it off or change how often in Settings › General.
- Settings › Permissions now shows whether Ribbon can send notifications. Check-ins and break reminders need them.
- Clicking one of Ribbon's notifications opens Today.

## 3.3

- **Uses far less CPU.** Ribbon used about 9% of your CPU just running in the background. Now it uses almost none: the orb no longer redraws itself when it's hidden or when no focus session is running, and its breathing during a session is handled by macOS.
- The orb's animation is simpler. It breathes slowly during a focus session and a little faster while it nudges you, and stays still otherwise. It no longer pulses with its voice.
- Ribbon asks your browser for the current tab's address only when the tab may have changed, instead of every 5 seconds.

## 3.2

- **More accurate context switches.** A switch now counts only when you stay in the new app or website for at least 10 seconds, so quick glances don't count.
- Opening Ribbon's own dashboard, settings or orb no longer counts as a context switch.
- Fixed: when Chrome didn't report a tab's address for a moment, Ribbon recorded you as leaving the site and coming back. Ribbon now keeps the site you were on.

## 3.1

- **Automatic updates.** Ribbon checks for new versions, shows you what's in them, and installs them when it restarts. You can turn this off in Settings › General.
- **Check for updates yourself** from the menu bar icon, the Ribbon menu, or Settings › General.
- Relaunching Ribbon after you save an API key is more reliable.

## 3.0

- The first public release of Ribbon, the AI time tracker for Mac.
- Tracks the apps and websites you use, sorts them into categories with AI, blocks distractions during focus sessions, and answers questions about your time.
- Add your OpenAI API key in Settings › AI to turn on the AI features.
