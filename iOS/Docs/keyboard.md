# Sorla keyboard — prototype note (#66)

**Status:** prototype. Builds and passes its unit tests on the iOS Simulator. **Nothing here has run on a physical iPhone yet**; the device checklist at the end decides whether the approach holds.

## Why a keyboard

#70's scope said "no custom keyboard". The owner has since decided that pasting by hand after every dictation is not acceptable on iPhone, so this prototype evaluates the one way iOS lets a third-party app put text into another app's text field without the person pasting: a custom keyboard that inserts it with `textDocumentProxy.insertText`. #70's body is unchanged; the decision is recorded on #66.

## Journey

Tap into a text field → switch to the Sorla keyboard with the globe key → press the Action Button (Sorla opens briefly to start listening, as today; swipe back) → speak → press the Action Button again → Sorla transcribes on the phone → the text appears in the field.

## Architecture

```
Action Button → Shortcut → ToggleDictationIntent (app process)
                                   │ DictationCoordinator.onPhaseChange ──► phase → App Group UserDefaults + Darwin "se.sorla.ios.phase-changed"
                                   │ outcome .transcribed(text), non-empty ─► pending-transcript.json in the App Group + Darwin "se.sorla.ios.transcript-ready"
                                   ▼
                         Shortcut still gets Outcome / Ready to Paste / Text (contract unchanged)

SorlaKeyboard (keyboard extension, own process)
  observes both Darwin notifications, and also checks on viewWillAppear and textDidChange
  → claims the pending file once → textDocumentProxy.insertText(text) → file deleted
  → status line from the published phase
```

- **Targets.** `SorlaKeyboard` (`com.sorla.ios.keyboard`, `app-extension`, `com.apple.keyboard-service`) is embedded in the app. Info.plist: `RequestsOpenAccess = true`, `IsASCIICapable = false`, `PrimaryLanguage = sv-SE`, `PrefersRightToLeft = false`.
- **App Group** `group.com.sorla.ios` on the app and the keyboard (entitlements generated from `iOS/project.yml`). The Live Activity doesn't need it.
- **Shared code.** `iOS/Handoff/TranscriptHandoff.swift` is Foundation only and is the only code the keyboard shares with the app: no SorlaCore, no FluidAudio, no model, no audio. The keyboard itself is UIKit (no SwiftUI), so it stays far below the ~60–70 MB a keyboard extension may use.
- **Delivery record.** `{id, text, createdAt}` as JSON in `<App Group>/Handoff/pending-transcript.json`, written atomically. A newer transcript replaces an unclaimed one.
- **Single delivery.** The keyboard first renames the file to a name only it knows (a rename succeeds for exactly one caller, so two keyboard instances can't both take it), then reads and deletes it, and remembers the last 32 delivered ids (ids only) in the App Group's UserDefaults; a record whose id was already delivered is deleted unused.
- **Expiry.** A record is valid for 5 minutes, the same lifetime as the Mac app's Recent Transcript (`RecentTranscript.lifetime`). An expired record is deleted unused by whichever side looks first: the keyboard on every check, the app on launch. A record whose `createdAt` lies in the future (clock set back) counts as expired.
- **Phase.** `idle`, `listening`, `captured` (capture ended by itself; the next press transcribes) or `transcribing`, with the time it was written, in the App Group's UserDefaults. The app writes `idle` on launch (a new process owns no dictation) and on every change; a phase older than 10 minutes reads as `idle`, so a process that died mid-dictation can't leave the keyboard saying "Lyssnar…".
- **Where the app publishes.** `DictationCoordinator` reports each phase change through `onPhaseChange`; `DictationRuntime` passes it, and each finished outcome, to `KeyboardHandoffPublisher`, which hands over only `outcome.textToCopy` (a successful, non-empty transcript — the same rule as the Shortcut's Ready to Paste). A hand-over that fails is logged as `diagnostic.keyboard: …` with the error domain and code only.

## Privacy

- The text exists in the App Group container only between the stop press and the keyboard inserting it, at most 5 minutes (deleted then, or at the next check by either side if neither runs at that moment).
- The file has **complete-unless-open** data protection (`.completeFileProtectionUnlessOpen`): its key is discarded when the iPhone locks, so it can't be read while locked, but Sorla can still create it if the phone locks during a transcription. Plain `.complete` would make that write fail. The Handoff folder is excluded from backup.
- Text is never written to UserDefaults, never logged by the app or the keyboard, and never sent with a notification (Darwin notifications carry a name only).
- The keyboard makes no network requests and has no analytics. It never reads what is typed with it; `textDidChange` is used only as a moment to check for a waiting transcript.
- The app itself still never writes the clipboard.

## Full Access, and what it means here

iOS keeps a keyboard extension out of its App Group container unless the person turns on **Tillåt full åtkomst** (Allow Full Access). Without it the Sorla keyboard cannot receive text from Sorla; it still works as a minimal keyboard (globe, space, delete, return) and shows: "Slå på Tillåt full åtkomst för Sorla i Inställningar › Allmänt › Tangentbord › Tangentbord › Sorla för att ta emot text från Sorla."

iOS shows a general warning when Full Access is turned on (a keyboard with Full Access *could* send what you type over the network). For Sorla, Full Access is used for one thing: reading the transcript Sorla left in the shared container. The keyboard has no network code, keeps no history and reads no typed text. This has to be said in the app and the privacy policy before any release (#70).

## Clipboard and the Shortcut

The Shortcut contract doesn't change: the intent still returns Outcome, Ready to Paste, Text and Message, and still works without the keyboard. With the Sorla keyboard enabled **and** Full Access on, the Shortcut's **Copy to Clipboard** step is unnecessary and can be removed (keep **If Ready to Paste is true** → **Vibrate Device** as the ready cue, if wanted). Removing it keeps the transcript off the clipboard entirely. If the Copy step stays, the text is both inserted and on the clipboard.

No intent property was added: whether the keyboard is showing when the result arrives isn't known to the app at that moment, so a "delivered to keyboard" flag would be a guess.

## Strings

Swedish when the iPhone's first preferred language is Swedish, English otherwise (in code, `Keyboard/KeyboardStrings.swift`; localisation proper is #69).

| State | Svenska | English |
|---|---|---|
| idle | Tryck på Åtgärdsknappen för att diktera | Press the Action Button to dictate |
| listening | Lyssnar… | Listening… |
| captured | Pausad – tryck på Åtgärdsknappen igen | Paused – press the Action Button again |
| transcribing | Skriver… | Writing… |
| inserted | Infogat (until the next dictation starts; also announced to VoiceOver) | Inserted |

Keys: globe (`Nästa tangentbord`, shown only when `needsInputModeSwitchKey`; tap for the next keyboard, touch and hold for the list via `handleInputModeList`), `mellanslag`, `Radera` (delete backward), `retur`. Every key has a VoiceOver label and the keyboard-key trait; labels and keys use Dynamic Type text styles and grow with the text size.

## Setup on the iPhone

1. Install Sorla (the build includes the keyboard). Keep the model installed and the Action Button Shortcut as described in [action-button.md](action-button.md).
2. **Inställningar › Allmänt › Tangentbord › Tangentbord › Lägg till nytt tangentbord…** → under *Tangentbord från andra utvecklare* choose **Sorla**.
3. In the same list tap **Sorla** and turn on **Tillåt full åtkomst** (confirm **Tillåt** in iOS's warning).
4. Optional: in the Shortcut, remove **Kopiera till urklipp** (Copy to Clipboard); keep **Om** (If) *Ready to Paste* → **Vibrera enhet**.

## Using it

1. Tap into any text field (Notes, Messages, Mail…).
2. Switch to Sorla with the globe key (touch and hold the globe to pick Sorla from the list). The status line says *Tryck på Åtgärdsknappen för att diktera*.
3. Press the Action Button. Sorla opens briefly to start listening; swipe back to the app. The keyboard shows *Lyssnar…*.
4. Speak, then press the Action Button again. The keyboard shows *Skriver…*, then the text appears at the cursor and the status line says *Infogat*.

## Device test checklist

Build and install: see `iOS/README.md`. Record the iOS version and iPhone model, and copy the Dictation tab's log after the run.

**Setup**
- [ ] Sorla appears under *Tangentbord från andra utvecklare* and can be added.
- [ ] Without Full Access: the keyboard shows the Full Access line; globe, space, delete and return work; a dictation does **not** insert anything (and nothing is left in the container after 5 minutes).
- [ ] With Full Access on, the Full Access line disappears.

**Journey**
- [ ] Notes, Sorla keyboard showing: press, speak ~10 s, press → *Lyssnar…* → *Skriver…* → text inserted at the cursor → *Infogat*. Time from second press to text: ___ s.
- [ ] Same in Messages, Mail, Safari's address bar and a search field.
- [ ] Swedish characters (å, ä, ö) and punctuation are inserted correctly.
- [ ] Text is inserted exactly once (no duplicate) — also after switching away from the keyboard and back, and after leaving and returning to the app.
- [ ] Keyboard hidden when the text arrives (e.g. system keyboard showing), switch to Sorla within 5 minutes → inserted once. After more than 5 minutes → nothing inserted.
- [ ] Two dictations in a row → each text inserted once, in order.
- [ ] Stop press while the keyboard isn't in front, then open a *different* app's field with Sorla within 5 minutes: note whether the late insertion is surprising (this is the main UX risk of the 5-minute window).
- [ ] Cancel from the Live Activity, an empty recording, and a failure: nothing is inserted; the status returns to idle.
- [ ] Recording limit / call interruption: status shows *Pausad – tryck på Åtgärdsknappen igen*; the next press inserts the text.
- [ ] Force-quit Sorla while listening: the keyboard's status returns to idle (at the latest after 10 minutes, or at once when Sorla is opened again).
- [ ] Phone locks during transcription: after unlocking with the keyboard showing, the text is inserted (within 5 minutes).

**Clipboard**
- [ ] Shortcut without the Copy step: put a known string on the clipboard, dictate → text inserted, clipboard still holds the known string.
- [ ] Shortcut with the Copy step: text inserted and on the clipboard (one write).

**Keyboard behaviour**
- [ ] Globe: tap switches to the next keyboard; touch and hold shows the list. On a device without the need for a globe key (`needsInputModeSwitchKey == false`), it's hidden.
- [ ] VoiceOver: every key is read with its label; *Infogat* is announced after insertion.
- [ ] Largest Dynamic Type sizes: status line wraps, keys grow, nothing is cut off.
- [ ] Dark mode and light mode look right.
- [ ] Memory: in Xcode's debug navigator (attach to *SorlaKeyboard*), the keyboard stays well below 60 MB while showing and inserting.

**Privacy**
- [ ] Console (`log stream --predicate 'subsystem == "com.sorla.ios"'`) and the Dictation log contain no transcript text.
- [ ] After a delivery, the App Group's Handoff folder is empty (check with a development build and Xcode's container download, if needed).

### Go/no-go for the keyboard

Go if the text reliably arrives once, in the focused field, within a second of the transcript being ready, without the person pasting, with Full Access as the only extra permission, and the keyboard stays within its memory limit. Otherwise record which step failed and whether a different hand-over (e.g. shared UserDefaults instead of the file) would help.
