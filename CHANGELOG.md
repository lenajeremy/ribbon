# Changelog

Ribbon shows the section for a new version when it offers you the update.

## 3.16

- **A new voice for the orb.** Add a Gemini API key in Settings › AI and the orb speaks with Gemini 3.8 Flash TTS instead of the macOS voice. Its own voice is a cold, bone-dry English butler, made in your Google project the first time it's used. You can pick any of Gemini's 30 built-in voices instead, and play a sample.
- **Each line is performed differently.** The AI that writes what the orb says also decides how to say it, like "a weary sigh, then clipped and icy", and can add a sigh or a pause.
- **How the orb talks to you.** Under Settings › AI, choose Friendly (playful, never mean) or Ruthless: it mocks the distraction, holds you to your goal and gets colder each time you ignore it. It goes after what you're doing, never who you are. Check-in notifications follow the same choice.
- With a Gemini key, what the orb says aloud is sent to Google to be turned into speech.

## 3.15

- Sites are blocked in the Chrome you're using even when another copy of Chrome is running. Tools that test or record web pages can start their own copy, and Ribbon was reading that copy's page instead of yours, so nothing in your Chrome got blocked.
- If Ribbon can't see which site is open in your browser during a session, the orb now says so, instead of letting every site through without a word. If Ribbon's permission to control the browser is off, it says where to turn it back on, and picks it up again without a restart.

## 3.14

- **The running session on Today.** While a focus session is on, the top of Today shows its session type and task, a live countdown with how much of this focus part or break is done, and for a scheduled session, how much of the whole day's session is done and left.
- Pause, resume, end or end a break from there too, whenever the session allows it. A scheduled session offers only your emergency pass. Pausing, ending and the pass take the same hold and reason as at the orb.

## 3.13

- Restarting Ribbon to finish an update, or after saving an API key, now reopens the dashboard so you can see it's back. Before, Ribbon came back in the menu bar only, which looked like it had closed for good.

## 3.12

- During a focus session, Ribbon still can't be quit, but it no longer stops your Mac from logging out, restarting or shutting down. A scheduled session picks up again after you log back in.
- An update waits until a scheduled session is over before it restarts Ribbon, breaks included.

## 3.11

- **Scheduled focus sessions.** Under Focus sessions › Schedule, choose a session type, what you'll work on, the days and the times, like 9:00 to 17:00 on weekdays. The session starts by itself, and its rules stay on until the end time, breaks included. A scheduled session can't be paused or stopped.
- **Emergency pass.** You get one a week, from Monday. It's the only way to end a scheduled session early, and it ends that day's session.
- If Ribbon is quit during a scheduled session, it reopens within a minute and carries on. A small background helper does this; you'll see it under System Settings › General › Login Items while you have a schedule turned on.

## 3.10

- Fixed: when you were signed in with ChatGPT, Ribbon's AI didn't work. Summaries, sorting, check-ins, session reviews, Ask AI and the orb's checks all failed or came back empty. They now work on your ChatGPT plan.

## 3.9

- **Use your ChatGPT plan.** In Settings › AI, choose Continue with ChatGPT to sign in. Ribbon's AI then uses your ChatGPT Plus or Pro plan instead of an API key, sharing its allowance with ChatGPT and Codex. You can see usage and set a weekly limit for Ribbon in ChatGPT settings, and pick which of your plan's models Ribbon uses.
- On your ChatGPT plan, the orb speaks with a macOS voice and checks your screen every 30 seconds to spare your allowance. If the plan's limit is reached, Ribbon pauses its AI and tells you.
- An API key still works as before.
- Fixed: the API key's Save button could be squeezed into a blank circle.

## 3.8

- Removing a session from Recent sessions is now one click: point at the session and click the ✕ that appears on the right. Removed sessions show ↩ instead, to put them back. Right-clicking still works.

## 3.7

- **Clean up Recent sessions.** Right-click a session under Focus sessions › Recent sessions and choose Remove from List. It only leaves the list: its time still counts in your day, and Ask AI still knows about it. To bring one back, click "Show removed sessions" at the bottom of the list, then right-click it and choose Put Back in List.

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
