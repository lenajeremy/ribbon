# Changelog

Ribbon shows the section for a new version when it offers you the update.

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
