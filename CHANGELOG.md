# Changelog

## Unreleased

- Updates for Sorla and the speech model live in one place, Settings › Updates: a row for each with its version and result, one Check Now that asks GitHub and Hugging Face together, and two toggles (check automatically, install automatically) that replace the model-only ones and keep their values. Check for Updates… in the menu opens that section and runs the check, a newer Sorla shows in the menu's status row, and the About window is back to just the version.
- Sorla no longer uses notifications, so macOS never asks for a third permission. Problems show in the indicator (an hourglass while the model gets ready, a warning when something failed), VoiceOver announces them, and the menu's status row explains the last dictation (muted microphone, text on the clipboard, no microphone, failed transcription) until the next one starts or for five minutes.
- The update check tells "offline", "GitHub rate limit" and "bad response" apart and never shows a failure as "up to date".
- About window: calmer layout with the Klang Pianissimo credit up front, links to the website, GitHub and privacy page; other credits and the license texts are in Credits and Licenses….
- When the model couldn't be loaded, dictation is refused up front with a pointer to Try Again in the menu.
- Cancelling a recording while an earlier one is still being transcribed no longer hides the indicator early or lets a model update swap in mid-transcription.
- Something you copy between two quick dictations is kept instead of being replaced by the older clipboard content.
- A modifier trigger only stops recording once the key is really up, and Sorla's own paste can't read as a release.
- A dictation that gives no text now says why: the indicator briefly shows a symbol (nothing heard, no text, muted microphone, text on the clipboard) and VoiceOver announces it; a muted microphone also shows while recording.

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
