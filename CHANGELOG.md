# Changelog

## Unreleased

- Install and update with Homebrew: `brew install --cask markstrom/tap/sorla`.
- Sorla lets go of the recorded audio as soon as the recording stops, instead of holding it until the next one. A cancelled recording, or one cut short by locking the Mac, is dropped without being converted or transcribed.
- When you start a new dictation while the previous one is still being transcribed, the texts arrive in the order you spoke them, and Paste Last holds the newer one. A dictation that fails or gives no text doesn't hold up the next, and each text is only written to the clipboard once the previous paste has had time to land. Only that write waits: a cue, a failure or the first paste is never held up by it. A transcription that never finishes is given up as failed after a generous limit (three times the recording's length, at least 30 seconds), so it can't hold back the dictations after it.
- Paste Last from its shortcut (⌃⌥V) no longer pastes while the shortcut's keys are still held after its one-second wait, which reached the app as ⌃⌥⌘V. Nothing is pasted and your clipboard is left alone; Sorla asks you to "Let go of the keys and press ⌃⌥V again", and the text is still there for Paste Last. Locking the Mac or starting a dictation while it waits cancels it.
- With VoiceOver on, Sorla says "Pasting text" instead of "Pasted", since it can tell that it sent the paste but not that the app accepted it. Announcements also wait until the microphone has really closed, including the short tail after you let go, so a result that arrives while the next recording is ending isn't recorded into it.
- New setting, Keep last transcription (on by default). Turned off, Sorla keeps no text for Paste Last once a dictation has been pasted: what was kept is forgotten at once, a Paste Last on its way is called off, and Paste Last and its shortcut are unavailable. Dictation itself pastes as before.
- Settings, About and Welcome open the same way: a minimised window is restored, the window comes to the Space you are on (also over a full-screen app) instead of taking you to another one, and it is made the key window once Sorla has actually become active. This should keep them from opening behind other windows. A window you close while it is still waiting to come forward stays closed, instead of reappearing when Sorla is next activated.
- Settings, About and Welcome open the same way: a minimised window is restored, the window comes to the Space you are on (also over a full-screen app) instead of taking you to another one, and it is made the key window once Sorla has actually become active. This should keep them from opening behind other windows.
- Esc cancels a recording in either mode, whether it was started with the key or from the menu.
- In push-to-talk, a click once the recording has begun (past the first 0.3 s) no longer throws it away, so a stray click or opening the menu to choose Stop Dictation keeps what you said. A key pressed with the trigger held, such as Right ⌘ + C, still cancels.
- A cancelled recording says so: the indicator briefly shows a cross and VoiceOver says "Recording cancelled" once the microphone has closed. A ⌘-shortcut made with the trigger key, or a press shorter than 0.3 s, still goes quietly.
- With Sticky Keys, a trigger key that is latched instead of released no longer turns the next key press or click into a cancel: if the key is up by then, Sorla acts as if you had let go, so a push-to-talk recording ends, a Toggle tap starts or stops, and a press after Esc or Right ⌘ + C works again. Fn is left out, since its key state can be out of date and would end a real hold. This hasn't been verified on a Mac with Sticky Keys yet; Esc and Stop Dictation in the menu always end a recording.
- The Welcome window suggests Toggle mode (press once to start, again to stop) for anyone who finds holding a key down hard.
- When Sorla.app is replaced on disk while Sorla is running (a new version dragged into Applications without quitting), macOS silently drops its pastes. Sorla now notices when you open its menu or before it pastes: the menu shows "Sorla has been updated — Restart", which quits and opens the new version once the old one has exited, and a dictation or Paste Last in the meantime is left on the clipboard for ⌘V and kept for Paste Last instead of vanishing.

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
