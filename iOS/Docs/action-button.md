# Action Button dictation — technical decision note (#66)

**Status:** prototype builds for the iOS Simulator and its state model is unit-tested. Two device runs on an iPhone 16 Plus (iOS 27.0) have shaped the design: **iOS will not start audio input from the background**, so Sorla opens briefly on the start press (see *Starting needs the foreground*), and the mixable session tried for a background start captured only zeros, so the session is back to the non-mixable `.record` that captured real speech. Both changes wait for a third run. **Apart from what is quoted from those runs, nothing in this note has been verified on a physical iPhone.** Every other statement about runtime behaviour on a device is a design assumption to be checked with the procedure at the end. Go/no-go is open until that is done.

## The journey being proven

Press the Action Button (or Back Tap) → Sorla opens briefly and starts listening, and the Shortcut finishes at once (the user can swipe back to where they were; Sorla keeps listening in the background) → release and speak → press again → Sorla stops the microphone, transcribes on the phone and returns the text → the Shortcut copies it only if there is text → the user picks any field and pastes.

## Decisions

### One App Intent in the app process: `ToggleDictationIntent: AudioRecordingIntent`

- `AudioRecordingIntent` (iOS 18+) is the system protocol for an intent that records audio. Apple's documentation for it requires the app to start a Live Activity when recording begins and keep it while recording; otherwise the system may stop the recording. The prototype therefore refuses to start (outcome `failed.liveActivityUnavailable`) when Live Activities are off, instead of recording audio it may lose.
- The intent lives in the **app target, not an App Intents extension**: the microphone session, the loaded model and the state must survive from the first invocation to the second, so both have to run in the same process. The first invocation returns `started` as soon as the microphone is running; the Shortcut does not wait during dictation.
- iOS 27 adds `allowedExecutionTargets`; the default (main app) is what we want and is left alone.

### Starting needs the foreground: `supportedModes = [.background, .foreground(.dynamic)]`

**Device evidence (second run, iPhone 16 Plus, iOS 27.0).** With Sorla in the background, the Action Button start now activated the session (`playAndRecord`, `mixWithOthers+allowBluetoothHFP`, input `MicrophoneBuiltIn`, 48 kHz, 1 ch), but starting the engine failed: `com.apple.coreaudio.avfaudio` 2003329396, failed call `PerformCommand(*ioNode, kAUStartIO)`. iOS refuses to *start* audio input from the background, `AudioRecordingIntent` or not. The first run had already failed one step earlier, at activation (`'!int'`). So a recording has to start with Sorla in the foreground; once running, it may continue in the background (`UIBackgroundModes` `audio`).

**Mechanism.** The intent declares `supportedModes = [.background, .foreground(.dynamic)]` (iOS 26 API; the extracted metadata shows `supportedModes 9` and the `ForegroundContinuable` system protocol). It runs in the background as before; only when a trigger is about to *start* listening and Sorla is not already active does it call `continueInForeground(_:alwaysConfirm: false)` and wait (at most 2 s) for the app to become active before the microphone starts. The coordinator decides (`DictationCoordinator.toggle(foreground:)`), so the rule is unit-tested:

| Trigger | Sorla | What happens |
|---|---|---|
| start | already active (in front) | starts in place, nothing opens |
| start | in the background, iOS allows coming forward | Sorla opens, then starts listening |
| start | in the background, iOS doesn't allow it (`canContinueInForeground` false), or the transition is refused | `Failed` (`foregroundUnavailable`, “Sorla has to open to start listening. Unlock the iPhone and try again.”); the microphone and Live Activity are never started |
| start that the checks refuse (lost session, microphone, model) | any | the failure is returned without opening Sorla |
| stop, busy, cancel | any | stays in the background; transcription runs there |
| any trigger while Sorla is coming forward | — | `Busy` |

Alternatives, and why not: `openAppWhenRun` (deprecated in iOS 26) and `.foreground`/`.foreground(.immediate)` would open Sorla on the *stop* press too, just when the user is in the app they want to paste into; `.foreground(.deferred)` always ends in the foreground; `ForegroundContinuableIntent.requestToContinueInForeground` is deprecated in iOS 26 in favour of `.foreground(.dynamic)` and always asks. `.foreground(.dynamic)` is the only mode that opens Sorla for the start alone.

**What the user sees.** Press → Sorla's window opens (from another app, the Home Screen, or after unlocking) and the Live Activity / Dynamic Island shows “Listening”; the orange microphone indicator is on. They can speak at once, or swipe up (or use the app switcher) to go back to where they were; Sorla keeps listening in the background. Press again → nothing opens; the Live Activity changes to transcribing, and the Shortcut copies the text. With `alwaysConfirm: false`, iOS may still ask once (“Continue in Sorla?”) if it has no recent confirmation; whether it does, and whether the Lock Screen demands unlocking first, is for the device run. Each foreground start logs `diagnostic.foreground` with how long it took. Deployment target is iOS 26.0 for this (see below).

### Explicit result, and the clipboard is written by the Shortcut only

`perform()` returns `DictationResultEntity` (a `TransientAppEntity`) with:

| Property | Meaning |
|---|---|
| Outcome | `Started`, `Transcribed`, `Nothing Heard`, `Cancelled`, `Busy`, `Failed` |
| Ready to Paste | true only for `Transcribed` with non-empty text |
| Text | the transcript, only when Ready to Paste |
| Message | a short status sentence, never the transcript |

Sorla never calls `UIPasteboard` in this flow. The Shortcut copies **Text** only inside `If Ready to Paste is true`, so start, cancel, busy, failure and empty recognition leave the clipboard untouched (the agreed iOS rule). The entity's display representation is the Message, so Shortcuts' output preview doesn't show the transcript.

### Audio

- **Session: `.record`, mode `.default`, options `.allowBluetoothHFP`, not mixable** (`DictationSessionConfiguration.dictation`), category and mode set before `setActive(true)` on every start, deactivated (`notifyOthersOnDeactivation`) the moment capture stops. `UIBackgroundModes` contains `audio`, which is what lets an active recording continue in the background; once the session is inactive the app is an ordinary background app again. There is no silent playback and no dummy recording. Other audio (music, a podcast) is interrupted while dictating, as a recording app normally does.
  - *History.* The first run used this session and captured real speech in the foreground (peak −3.2 dBFS, correct text), apart from the first recording after launch (zeros). A background start then failed at activation with `'!int'` (a background app may only activate a mixable session), so the second run tried `.playAndRecord` + `.mixWithOthers`. That got past activation in the background but not past `kAUStartIO` (above), and **in the foreground every recording came back as zeros** (peak `-inf` dBFS) — with “input route appeared, started over on a new engine” and two “first second silent, started over” restarts per recording, then `failed.silentInput`. Since recording can't start from the background anyway, mixability buys nothing, and the session went back to what worked.
- **One long-lived `AVAudioEngine`** (`SharedEngineAudioInput`), made by the *first* start after the session is configured and active — not at launch — and reused by every later recording. Every start re-reads the input format (`inputNode.inputFormat(forBus: 0)`) and installs the tap with it; stop removes the tap and stops the engine. The engine is reset only on a real `AVAudioEngineConfigurationChange`, and dropped only on a media-services reset. Audio stays in memory and is dropped as soon as it has been transcribed, cancelled or found empty.
  - *Why this should fix both silent cases.* (1) First recording after launch: before the second run, the one engine was created in the app's `init`, while the session category was still the default playback-only one, and its first use delivered zeros; later uses of the same engine worked. Creating it only after the session allows input removes that difference. (2) The all-zero foreground recordings: they came with the mixable `.playAndRecord` session and a brand-new engine per recording, restarted up to three times; neither the new engines nor the restarts helped. Back on `.record` with one engine, the only configuration seen to capture speech on the device, and without restarts that tear down a running engine. This is the most likely cause, not a proven one; the `diagnostic.engine` row (new or reused engine, recording number, input and node formats) and `diagnostic.audio` of the third run will show it.
- **Restarts that stay.**
  - *Silent start* (the whole first second below −90 dBFS; seen only right after the intent brought Sorla forward, never on a plain launch: 5 of 5 fresh-launch probes had sound from 0.0 s). Only in the foreground, **up to three times** per recording: the recorder drops the silence, stops and discards the engine, deactivates the session, waits 200, 400, then 600 ms, sets the session up and activates it again, and starts a **new engine**; a restarted input counts as dead after 0.5 s of zeros, so the last restart comes about 3.5 s after the start (plus the activations). On device run 4 a single immediate new-engine restart recovered once and failed once; the pauses give the foreground transition and the route time to settle. Sound on any attempt is kept (without the dropped silence) and logged with the time it took. If it is still silent after the third restart, it is only logged; the dropped silence is handed back with the rest, so the stop reports `failed.silentInput` and never a short or empty recording — also when the stop comes during a pause. A stop, cancel, interruption or configuration change during a pause never restarts anything; going to the background during a pause ends capture (a non-mixable session can't be activated there). A silent start already in the background is only logged.
    - *Why not wait longer before the first start.* The first start already waits until the app is `.active` (the state `didBecomeActive` announces) after `continueInForeground`; the app was active 377–533 ms after the press on device run 4, and the silent starts still happened. Holding every start back for a fixed settle time would cost latency on the starts that work, so the waiting happens only when the input turns out to be dead. `diagnostic.session` now also says whether the session reports an input and whether other audio was playing, to compare a silent start with a good one.
  - *Engine configuration change* (route or format; the engine has stopped itself): reset the same engine, re-read the format and carry on at the same rate, keeping the audio. At another rate: if nothing has been heard yet, start over at the new rate; otherwise capture ends and keeps what was heard (audio at two rates can't be joined). At most three per recording.
  - *Dropped:* starting over when an input route “appears” after activation (that route change is a normal part of activating the session; acting on it tore down the engine at 0 s).
- A call, Siri or a media-services reset **ends capture but keeps what was heard**; the Live Activity changes to “Stopped — trigger again to transcribe” and the next trigger transcribes it (a media-services reset also drops the engine; the next start makes a new one). The microphone is never left open waiting for the user.
- **Going to the background mid-recording** keeps capturing on the running engine (`UIBackgroundModes` `audio`, session still active); `diagnostic.background` logs the seconds listened and the peak so far, and the stop's `diagnostic.audio` shows whether sound reaches the end.
- **Silence is a failure, not “nothing heard”.** A capture long enough to hold speech whose peak stays below −90 dBFS ends as `failed.silentInput` (“The microphone delivered no sound.”), which is not the same as `nothingHeard` (too short, or speech the model returned no words for).
- A dictation stops capturing by itself after **120 s** (prototype value; the Mac uses 5 min). The final limit should come from the #65 latency and background-time measurements.

### Bounded work after stop

- The model starts loading (and warms up on 1 s of silence, like the Mac) at the first trigger, while the user speaks, so the second trigger usually finds it ready. The log records whether it was.
- Transcription runs inside `UIApplication.beginBackgroundTask`. Its expiration handler ends the dictation as `failed.backgroundTimeExpired`; `backgroundTimeRemaining` at stop is logged.
- A time limit of `max(30 s, 3 × audio length)` (same formula as the Mac) ends a hung transcription as `failed.timedOut`.
- An abandoned transcription (timeout, expiry, cancel) may still finish inside the engine; its result is discarded and can never be returned by a later trigger.
- Not used: `BGContinuedProcessingTask` (iOS 26). It is meant for long user-started work with a system progress UI; revisit only if device results show transcription regularly outliving the background task.

### Memory

The model stays loaded between dictations for speed and is unloaded on a memory warning when idle. Whether a backgrounded app holding the model survives, and how often it is terminated, is exactly what #65 and the device tests must show. `com.apple.developer.kernel.increased-memory-limit` is a possible entitlement if the numbers require it; it needs signing and is part of #70.

## Deployment target

**iOS 26.0**, the minimum for `supportedModes` / `.foreground(.dynamic)` / `continueInForeground`, which the start now needs (the note's earlier plan: raise the target rather than branch). `AudioRecordingIntent` needs 18.0; everything else used (`TransientAppEntity`, `LiveActivityIntent`, `AVAudioApplication`, ActivityKit) is older. An older test phone must run iOS 26. The shipping minimum is decided from #65: supported iPhones will be limited by memory and Neural Engine speed long before the OS version matters.

## State model

All state lives on the main actor in `DictationCoordinator`, so triggers are handled one at a time.

| Phase | Trigger (toggle) | Cancel (Live Activity button) | Capture ends by itself (limit, call, route) |
|---|---|---|---|
| idle | checks → (from the background: bring Sorla forward) → start → `Started`; or `Failed(…)` without touching the microphone | nothing to cancel | ignored |
| listening | stop microphone → transcribing | discard audio → `Cancelled` | stop microphone, keep audio → captured |
| captured | transcribe the kept audio | discard audio → `Cancelled` | — |
| transcribing | `Busy` (the running one keeps its result) | the pending trigger returns `Cancelled`; late text dropped | — |

Start checks, in order: a leftover **session marker** (a timestamp in `UserDefaults`, written at start and cleared at every end) means the process that was recording died — system termination or force-quit — so the trigger reports `failed.sessionLost` and ends any stale Live Activity instead of starting a new recording by surprise; then microphone permission (`failed.microphoneNotAuthorized`; the prompt can only be shown in the app); then an installed model (`failed.modelMissing`, so no words are recorded that can't be transcribed); then, when the intent runs in the background, bringing Sorla forward (`failed.foregroundUnavailable`; a trigger meanwhile is `Busy`); then the Live Activity; then the microphone.

A transcription ends in exactly one of: `Transcribed(text)`, `Nothing Heard` (too short, or whitespace-only text), `Failed(silentInput | transcriptionFailed | timedOut | backgroundTimeExpired)`, `Cancelled`.

Unit tests (`iOS/Tests/DictationCoordinatorTests.swift`, no sleeps — fakes resume on command) cover: prompt start, preload, each refused start, stop-before-transcribe, empty/short audio, silent input (zeros and below −90 dBFS) as `failed.silentInput`, failure, timeout, background expiry, busy during transcription, consecutive dictations, cancel while listening/captured/transcribing, late result after cancel not leaking into the next dictation, limit and interruption keeping audio, lost session, the session and audio diagnostic rows, metrics never containing text, and the foreground start: brought forward before the Live Activity and microphone, not when already active or when the intent already runs in the foreground, never for stop or for a start the checks refuse, `foregroundUnavailable` when iOS won't allow it or the transition fails, a still-inactive app logged, and `Busy` while coming forward. `iOS/Tests/LiveDictationRecorderTests.swift` drives the real recorder with a fake session and a fake microphone. It covers the non-mixable `.record` configuration, configure → activate → engine order, a refused activation never touching the engine, one engine for every recording, no restart on a route that appears after activation, up to three spaced foreground restarts on a new engine after a silent start (sound on any attempt kept and logged, the silence handed back when it never ends so the stop is `silentInput`, nothing restarted after a stop, cancel or configuration change during a pause, capture ended when backgrounded during a pause, none in the background), configuration changes (carry on, start over at a new rate, or end capture; bounded), interruptions, media-services reset (while recording and between recordings) and the background row with capture going on.

## Privacy

No audio is written anywhere. Transcript text exists only in memory until it is returned to the Shortcut. The diagnostics log (`Dictation` tab, `os_log` category `Dictation`) records outcome names, timings, audio length and background time left — never text. Its `diagnostic.*` rows are numbers and system names only:

| Row | When | Content |
|---|---|---|
| `diagnostic.foreground` | a start that had to bring Sorla forward | came forward and how long it took, whether the app was active; or why not |
| `diagnostic.session` | every start, also a failed one, and every silent-start restart | category, mode, options, route input port (`none` if empty), session sample rate, input channels, whether an input is available, whether other audio was playing |
| `diagnostic.engine` | every start that reached the engine | new or reused engine and recording number, input (hardware) format and the input node's output format |
| `diagnostic.audioStart` | the microphone didn't start | the system error (e.g. `560557684`) |
| `diagnostic.audioRestart` | a silent start (each restart, its pause and ms since the start; sound after a restart and when; still silent after the last), an engine configuration change, or a media-services reset | reason and result |
| `diagnostic.background` | Sorla went to the background while listening | seconds listened so far, peak level so far |
| `diagnostic.audio` | every stop | samples, peak and RMS dBFS, where there was sound (`sound 0.4–9.1 s of 9.2 s` or `no sound in …`), seconds listened |
| `diagnostic.liveActivity` | the Live Activity was refused | the system's reason | Network use is limited to the model download from Hugging Face.

## Known restrictions and risks

- **Sorla opens on every start.** iOS doesn't let audio input start from the background (device evidence above), so the journey is not fully invisible: the start press shows Sorla until the user swipes back. The stop press doesn't.
- **Unverified on device.** The foreground transition (does iOS ask “Continue in Sorla?”, what happens on the Lock Screen), its Live Activity, how long the second invocation may run, and clipboard behaviour on a locked phone are all device questions.
- **Clipboard on a locked phone.** Shortcuts' Copy to Clipboard may be unavailable or behave differently while locked; the intent result is correct either way, but the journey may require unlocking before pasting. Record exactly what happens.
- **Process death between triggers.** If iOS terminates Sorla while recording (memory pressure) or the user force-quits it, the audio is lost; the next trigger says so (`sessionLost`) rather than starting a new recording. Frequency is unknown until tested.
- **Model memory in the background.** A ~0.6B-parameter model held in a background app raises termination risk; see #65.
- **Live Activities disabled** blocks dictation in this prototype by design.
- Strings are English except the intent's title; localisation is #69.

## Device verification procedure

### Build and install (needs a locally set signing team — see `iOS/README.md`; real signing is #70)

1. `iOS/Benchmark/make-utterances.sh` (optional), `xcodegen generate --spec iOS/project.yml`, open `iOS/SorlaiOS.xcodeproj`.
2. Set your team for the `Sorla` and `SorlaLiveActivity` targets locally, choose the **Release** configuration in the Run scheme, run on the iPhone.
3. In Sorla: *Dictation* tab → **Allow Microphone**; *Model* tab → **Download and Install**. Keep Live Activities on for Sorla (Settings → Sorla).

### The Shortcut to build

In Shortcuts, create **“Diktera med Sorla”**:

1. Add action **Diktera med Sorla** (from the Sorla app).
2. Add **If** → input: *Sorla Dictation Result* → **Ready to Paste** → *is* → **true**.
3. Inside If: **Copy to Clipboard** → input: *Sorla Dictation Result* → **Text**; turn **Local Only** on (keeps the text off Universal Clipboard).
4. Inside If, after the copy: **Vibrate Device** (the ready cue; a spoken/visual cue can replace it, record which).
5. Otherwise: **If** *Outcome* *is* **Failed** → **Show Notification** with *Message*.
6. Settings → Action Button → **Shortcut** → “Diktera med Sorla”. For Back Tap: Settings → Accessibility → Touch → Back Tap → Double Tap → “Diktera med Sorla”.

Use the **Dictation** tab's log (Copy Log as Markdown) for timings after each session.

### Physical-device checklist (from #66's acceptance criteria)

Record device model, iOS version, build (commit, Release), and for each item: result, trigger→listening and stop→copied times from the log, whether Sorla came to the foreground, and anything iOS showed.

**Journey**
- [ ] Unlocked phone, another app in front: press, release, speak ~10 s, press; ready cue arrives; choose an arbitrary text field; paste; text is correct.
- [ ] Same from the Home Screen and from the Lock Screen (note whether unlocking was required, and when).
- [ ] Back Tap runs the same Shortcut with the same result.

**Lifecycle**
- [ ] Warm start (Sorla recently used) and cold start (after reboot, Sorla not running).
- [ ] System termination: start dictating, open heavy apps until Sorla is terminated (or use Xcode's “Simulate memory warning” then kill), trigger again → `sessionLost`, no stale text, clipboard unchanged.
- [ ] User force-quit while listening → next trigger reports `sessionLost`; Live Activity is gone.
- [ ] Lock/unlock during listening and during transcription.
- [ ] Live Activities disabled for Sorla → `Failed` with the Live Activity message; microphone never turns on.
- [ ] Microphone denied → `Failed`; clipboard unchanged.
- [ ] Model removed (Model tab → Remove Installed Model) → `Failed`; clipboard unchanged.
- [ ] Airplane mode after install → full journey works offline.
- [ ] Memory pressure: dictate right after using camera/games; note terminations.

**Start and audio (the fixes from the second device run)**
- [ ] Action Button with another app in front: Sorla opens; note whether iOS asked “Continue in Sorla?” (first time and later), and how long until the Live Activity shows. Swipe back, speak ~10 s, press: nothing opens, the text is right. Log: `diagnostic.foreground: came forward …`, `diagnostic.session` with `record`, `allowBluetoothHFP`; no `diagnostic.audioStart`.
- [ ] Same from the Home Screen, and from the Lock Screen (note whether it asks to unlock, and what the Shortcut shows if you don't: `Failed` with “Sorla has to open …”).
- [ ] First dictation after a fresh launch (force-quit Sorla, then press the Action Button; and once more with the in-app button): real text; `diagnostic.engine: engine new …`, `diagnostic.audio` peak well above −90 dBFS, no `audioRestart`. If there are `audioRestart` rows, note how many restarts it took, the `sound after restart N, … ms after the start` row, and whether the text still came out (the words spoken during the silent part are lost).
- [ ] Second and third dictations in the same process: `engine reused, recording 2/3`, real text.
- [ ] Start with Sorla in front, go to the Home Screen after ~5 s, speak on for ~15 s, stop with the Action Button: the text covers the whole dictation; `diagnostic.background` shows the time you left, and `diagnostic.audio`'s sound range reaches the end of the recording.
- [ ] Music playing in another app, then dictate: the music should pause (non-mixable session) and may resume after; record what happens.
- [ ] Covering the microphone is not silence (the input still has noise), so it must not give `failed.silentInput`; that outcome should only appear when iOS delivers nothing. Record every `failed.silentInput` together with the `diagnostic.engine` and `audioRestart` rows before it.

**Triggers and interruptions**
- [ ] Two presses in quick succession (< 0.5 s); press during transcription → `Busy`, the first result is still copied exactly once.
- [ ] Cancel from the Live Activity (Lock Screen and Dynamic Island) while listening → nothing copied.
- [ ] Incoming phone call / FaceTime / Siri while listening → capture stops, Live Activity says “Stopped”; next press transcribes what was said before.
- [ ] Headset route change while listening (connect/disconnect AirPods, plug/unplug wired) → capture carries on (`diagnostic.audioRestart: configuration change, continued …`), or, if the new input runs at another rate after speech, stops like an interruption and the next press transcribes what was said. Also dictate *through* AirPods (start with them connected).
- [ ] 120 s limit reached → capture stops by itself; next press transcribes.

**Clipboard rule**
- [ ] Put a known string on the clipboard; run start, cancel, empty recording (press twice silently), failure cases: the clipboard still holds the known string after each.
- [ ] No duplicate copy: one successful dictation → one clipboard write (check with a clipboard-watching step or by pasting twice after copying something else in between).
- [ ] Nothing is ever listening without the Live Activity and the orange microphone indicator.

**Timing and limits (record numbers)**
- [ ] Trigger→listening latency, warm and cold.
- [ ] Stop→copied latency for ~5, 10, 30, 60 s of speech (log's stop→result plus Shortcut overhead observed with a stopwatch/screen recording).
- [ ] Background time left at stop (log) and any `backgroundTimeExpired` outcomes; the longest dictation that still completes while Sorla is in the background.
- [ ] Repeat the journey with **VoiceOver on**: announcements, the Live Activity is readable, the cue is perceivable.

### Go/no-go

Open. Go requires the journey to work without bringing Sorla to the foreground except the brief opening on the start press documented above (an accepted, precisely documented exception if the device run confirms it is brief and prompt-free), no clipboard writes outside successful non-empty results, no indefinite listening, and stop→copied within the budget agreed after #65.
