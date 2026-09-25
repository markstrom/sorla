# Changelog

## Unreleased

- Esc cancels a dictation started from the menu while Settings was open (#55).
- Paste Last with nothing kept (it expired, or the Mac locked) now says "Nothing to paste" with VoiceOver and shows a brief cue, instead of doing nothing (#60).
- The Welcome window's buttons say what they act on when reached with Tab or VoiceOver's list of controls, such as "Open Microphone in System Settings" and "Open Accessibility in System Settings" instead of two "Open System Settings" (#61).
- With VoiceOver, a download or install you started that fails now says so and why: Install and Relaunch (from Settings or the menu), and the speech model's Download and Try Again (from Settings, the Welcome window or the menu). Background checks and installs stay quiet, as before (#62).
- When a recording stops by itself at the five-minute limit, VoiceOver says "Recording stopped at the five-minute limit" once the microphone has closed. Until now only the dimmed bars warned about it (#63).
- When a dictation or paste is blocked by something you have to fix, Sorla now opens a window that says what and offers the fix, instead of leaving the explanation in its menu (#72). A missing microphone or Accessibility permission, or a speech model that is missing, failed to download or load, or has too little disk space (with the space needed), opens the Welcome window's checklist as **Set Up Sorla**; its Try it here field is always at the bottom and works once everything has a checkmark. When the text was recognized but couldn't be pasted for want of Accessibility, the text is kept, and the window says it is on the clipboard, as long as it still is: close the window, which takes you back to the app you were typing in, and press ⌘V there. A microphone that won't start gets "Sorla couldn't start the microphone" with **Open Sound Settings**; a muted or silent one keeps the crossed-out microphone in the indicator and gets no window. In push-to-talk the window opens only when you let go, never for Right ⌘ + C, a short press or a cancelled recording, and it waits for a dictation still in flight. **Not now** (or Esc) keeps the same problem from opening it again until Sorla restarts, unless it goes away and comes back. Only one such window is open at a time, and Sorla still uses no notifications.
- A Sorla whose app was replaced on disk no longer restarts by itself when you press the trigger (#43). It still doesn't record, and a window explains that the old copy can't paste and offers **Restart Sorla** or **Not now**. The restart, also from the menu's status row, waits until any recording, transcription, paste or clipboard restore has finished. A copy that can't reopen itself asks you to quit and open it from Applications instead.
- The Welcome window says whether automatic update checks and installation are on or off (both off by default) and has an **Update Settings** button that opens Settings › Updates. Showing it changes no setting and checks for nothing (#73).
- On macOS 27, Sorla calls the permission it needs for pasting by its new name, **Device Control and Data Access** (still **Accessibility** in macOS 14–26), in the Welcome and Set Up Sorla windows, the menu's status row and what VoiceOver and Voice Control hear, so it matches System Settings. The button still opens the page directly (Fixes #74).
- With automatic update checks off, Install updates automatically (greyed out in Settings) now has no effect for the speech model either: Check Now offers a newer model instead of installing it straight away. The stored choice is kept for when checks are turned on again, and turning checks off also stops an app update that was waiting to install itself (#73).

## 1.1.0 — 2026-09-24

- Sorla installs its own updates. When a check finds a newer version, **Install and Relaunch** in Settings › Updates or the menu's status row downloads exactly that release (the versioned `Sorla-X.Y.Z.dmg` the check saw, never whatever "latest" is by then) into a private folder, with a size cap and a check that it arrived whole. Nothing is touched until the app in it passes: mounted read-only and hidden, signed with Sorla's Team ID and bundle ID, notarized according to Gatekeeper, and exactly the version that was found and newer than the running one. It is then copied next to Sorla, checked again and swapped in at the same path, so permissions stay; Sorla waits for any recording, transcription, paste or clipboard restore in flight, relaunches once the old process has exited, and never reopens the old app. The previous version stays next to it (for example `Sorla 1.0.3.app`) until the new one has run for 30 seconds, so a new version that won't start leaves the old one to open. Any failure keeps the current version and says so, never as "Latest". Download stays as the fallback; a copy that can't be replaced (a folder you can't write to, or App Translocation) explains why, and a Homebrew install is told to run `brew upgrade --cask sorla`.
- A Sorla installed with Homebrew is recognised by the link Homebrew keeps to it in its Caskroom (under `/opt/homebrew` or `/usr/local`), also when the app itself is in Applications, so it never replaces itself behind Homebrew's back: Settings and the menu point to `brew upgrade --cask sorla` instead, and automatic installs leave it alone.
- Install updates automatically now covers Sorla too (only with automatic checks on, both off by default): a new version found by the daily check is downloaded and verified in the background and installed after 10 minutes without dictation, or at the next launch, never during a dictation. Afterwards the menu briefly says "Sorla was updated to X.Y.Z". The Settings hint says so.
- When Sorla.app has been replaced on disk while Sorla runs, pressing the trigger no longer records words that can't be pasted. The indicator shows a restart arrow in place of the red dot, VoiceOver says "Sorla has been updated — restarting", and Sorla restarts into the new version by itself (after any earlier dictation has landed), so the next press works. The menu bar icon gets a small restart badge as soon as Sorla notices the new copy, without waiting for a press. A Sorla that can't reopen itself (App Translocation) records as before and keeps the menu row and clipboard fallback.

## 1.0.3 — 2026-09-24

- Settings are grouped under Dictation, Pasting, General and Updates. "Keep clipboard content" is now "Put back what you had copied", with a line explaining what it does, and the window never grows taller than the screen (it scrolls instead).
- Install and update with Homebrew: `brew install --cask markstrom/tap/sorla`.
- Sorla lets go of the recorded audio as soon as the recording stops, instead of holding it until the next one. A cancelled recording, or one cut short by locking the Mac, is dropped without being converted or transcribed.
- When you start a new dictation while the previous one is still being transcribed, the texts arrive in the order you spoke them, and Paste Last holds the newer one. A dictation that fails or gives no text doesn't hold up the next, and each text is only written to the clipboard once the previous paste has had time to land. Only that write waits: a cue, a failure or the first paste is never held up by it. A transcription that never finishes is given up as failed after a generous limit (three times the recording's length, at least 30 seconds), so it can't hold back the dictations after it.
- Paste Last from its shortcut (⌃⌥V) no longer pastes while the shortcut's keys are still held after its one-second wait, which reached the app as ⌃⌥⌘V. Nothing is pasted and your clipboard is left alone; Sorla asks you to "Let go of the keys and press ⌃⌥V again", and the text is still there for Paste Last. Locking the Mac or starting a dictation while it waits cancels it.
- With VoiceOver on, Sorla says "Pasting text" instead of "Pasted", since it can tell that it sent the paste but not that the app accepted it. Announcements also wait until the microphone has really closed, including the short tail after you let go, so a result that arrives while the next recording is ending isn't recorded into it.
- New setting, Keep last transcription (on by default). Turned off, Sorla keeps no text for Paste Last once a dictation has been pasted: what was kept is forgotten at once, a Paste Last on its way is called off, and Paste Last and its shortcut are unavailable. Dictation itself pastes as before.
- Settings, About and Welcome open the same way: a minimised window is restored, the window comes to the Space you are on (also over a full-screen app) instead of taking you to another one, and it is made the key window once Sorla has actually become active. This should keep them from opening behind other windows. A window you close while it is still waiting to come forward stays closed, instead of reappearing when Sorla is next activated.
- Esc cancels a recording in either mode, whether it was started with the key or from the menu. Sorla hears Esc even when it's meant for another app, so one Esc to close a popup also throws away a Toggle dictation in progress.
- In push-to-talk, a click once the recording has begun (past the first 0.3 s) no longer throws it away, so a stray click or opening the menu to choose Stop Dictation keeps what you said. A key pressed with the trigger held, such as Right ⌘ + C, still cancels. A slow Right ⌘-click, such as selecting several files in Finder, therefore no longer cancels either: the recording goes on and ends as usual when you let go, with its text or "Nothing heard".
- A cancelled recording says so: the indicator briefly shows a cross and VoiceOver says "Recording cancelled" once the microphone has closed. A ⌘-shortcut made with the trigger key, or anything that ends a recording before its start sound plays (or would play, with sounds off), still goes quietly, so there is never a cross without a start sound before it.
- With Sticky Keys, a trigger key that is latched instead of released no longer turns the next key press or click into a cancel: if the key is up by then, Sorla acts as if you had let go, so a push-to-talk recording ends, a Toggle tap starts or stops, and a press after Esc or Right ⌘ + C works again. Fn is left out, since its key state can be out of date and would end a real hold. This hasn't been verified on a Mac with Sticky Keys yet; Esc and Stop Dictation in the menu always end a recording.
- The Welcome window suggests Toggle mode (press once to start, again to stop) for anyone who finds holding a key down hard.
- When Sorla.app is replaced on disk while Sorla is running (a new version dragged into Applications without quitting), macOS silently drops its pastes. Sorla now notices when you open its menu or before it pastes: the menu shows "Sorla has been updated — Restart", which quits and opens the new version once the old one has exited (it waits up to 30 seconds), and a dictation or Paste Last in the meantime is left on the clipboard for ⌘V and kept for Paste Last instead of vanishing; the indicator and VoiceOver add "Restart Sorla to paste again". A Sorla that macOS runs from a temporary copy (App Translocation, for example when opened straight from Downloads) can't be reopened from there, so the row asks you to quit and open it from Applications instead.

## 1.0.2 — 2026-09-24

- Updates for Sorla and the speech model live in one place, Settings › Updates: a row for each with its version and result, one Check Now that asks GitHub and Hugging Face together, and two toggles (check automatically, install automatically) that replace the model-only ones and keep their values. Check for Updates… in the menu opens that section and runs the check, a newer Sorla shows in the menu's status row, and the About window is back to just the version.
- Sorla no longer uses notifications, so macOS never asks for a third permission. Problems show in the indicator (an hourglass while the model gets ready, a warning when something failed), VoiceOver announces them, and the menu's status row explains the last dictation (muted microphone, text on the clipboard, no microphone, failed transcription) until the next one starts or for five minutes.
- The update check tells "offline", "GitHub rate limit" and "bad response" apart and never shows a failure as "up to date".
- About window: calmer layout with the Klang Pianissimo credit up front, links to the website, GitHub and privacy page; other credits and the license texts are in Credits and Licenses….
- When the model couldn't be loaded, dictation is refused up front with a pointer to Try Again in the menu.
- Cancelling a recording while an earlier one is still being transcribed no longer hides the indicator early or lets a model update swap in mid-transcription.
- Something you copy between two quick dictations is kept instead of being replaced by the older clipboard content.
- A modifier trigger only stops recording once the key is really up, and Sorla's own paste can't read as a release.
- A dictation that gives no text now says why: the indicator briefly shows a symbol (nothing heard, no text, muted microphone, text on the clipboard) and VoiceOver announces it; a muted microphone also shows while recording.
- Keyboard: Esc and ⌘W close the Settings, About and Welcome windows, ⌘Q quits from any of them, and the Try it here field gets focus as soon as it appears.
- The first menu item starts and stops dictation (Start Dictation (Hold Right ⌘) / Stop Dictation), so Voice Control, Switch Control and head-pointer users can dictate without the trigger key. The text lands in the app you were working in, and a press and release of the key also stops a dictation started from the menu (a ⌘-shortcut doesn't).
- With VoiceOver on, Sorla says "Pasted" once the text has been pasted, after the recording has ended, so the microphone never hears it.
- Welcome window with VoiceOver: the app icon and row symbols are no longer read out, a finished row says "Done", a busy one "In progress", each row is read as one group, and VoiceOver announces when Sorla is ready.
- The menu bar icon shows an exclamation mark in place of the dot when the model couldn't be loaded, and VoiceOver reads it as "Sorla (model couldn't be loaded)"; while transcribing it reads "Sorla (transcribing)".
- The Welcome window and the help page describe a finished row by its checkmark instead of its colour ("shows a checkmark", not "turns green").
- Warnings and hints in Settings and the Welcome window (the Fn key warning, the Login Items approval hint, a failed update's reason, the Accessibility restart hint) use a larger size and the primary text colour, so they stay readable with Increase Contrast.
- Settings with VoiceOver: Check Now, Download and Try Again say what they act on ("Check for updates now", "Try downloading the model again"), and the Model row is plain text instead of a picker with a single choice.
- The last transcription is kept for Paste Last for five minutes, not until Sorla quits, and is forgotten at once when the screen locks, the Mac sleeps or you switch user. Paste Last is then unavailable until the next dictation. Locking, sleeping or switching user also cancels a recording in progress and drops a transcription that hasn't been pasted yet.
- A recording stops by itself after five minutes and what was said is transcribed and pasted as usual, so a forgotten toggle recording doesn't keep the microphone open. The indicator's bars dim during the last ten seconds.
- With automatic checks on, the speech model is checked about once a day, like Sorla itself, instead of at every launch.
- Start Dictation chosen while Settings or About is in front pastes into the app you were using before, like Paste Last.
- Closing the last Sorla window returns you to the app you were using, so a following ⌘Q doesn't quit Sorla by accident.
- With VoiceOver on, Settings notes under Play sounds that the sounds tell you when recording starts and stops.
- The two update toggles take their values from 1.0.1's model-only settings (autoCheckModelUpdates, autoDownloadModelUpdates), which are then removed; going back to 1.0.1 afterwards shows its automatic model checks and downloads as off.

## 1.0.1 — 2026-09-24

- Opening Sorla again while it runs shows Settings, since the menu bar icon can be hidden behind the notch.
- The Paste Last shortcut (⌃⌥V) works: Sorla waits for the shortcut's keys to be released before pasting.
- The shortcut fields in Settings are wide enough for longer translations and have accessible names.
- English tagline: "Talk. Release. Done."
- Check for new versions of Sorla with Check for Updates… in the menu (manual; asks GitHub only when you choose it).

## 1.0.0 — 2026-09-24

The first public release.

- Push-to-talk dictation in Swedish: hold a key, speak, let go, and the text is pasted where the cursor is.
- Toggle mode: press once to start and once more to stop.
- Choice of trigger key: Right ⌘ (default), Right ⌥, Right ⌃ or a custom shortcut.
- A small recording indicator at the top of the screen with a live waveform.
- Paste Last (⌃⌥V) pastes the most recent transcription again.
- The clipboard is kept: what you had copied is restored after pasting.
- Start and stop sounds.
- Launch at login.
- On-device speech recognition with Klang Pianissimo, downloaded on first launch. Model updates are checked only when you ask, or automatically if you opt in.
- A welcome window that guides you through Microphone and Accessibility access and the model download.
- English and Swedish user interface.
