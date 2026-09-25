# Action Button dictation — technical decision note (#66)

**Status:** prototype builds for the iOS Simulator and its state model is unit-tested. A first run on an iPhone 16 Plus (iOS 27.0) found two audio faults: the background start was refused (`'!int'`), and some captures were silent. Both are addressed under *Audio* and wait for a second run. **Apart from that, nothing in this note has been verified on a physical iPhone yet.** Every statement about runtime behaviour on a device below is a design assumption to be checked with the procedure at the end, not a result. Go/no-go is open until that is done.

## The journey being proven

Press the Action Button (or Back Tap) → Sorla starts listening and the Shortcut finishes at once → release and speak → press again → Sorla stops the microphone, transcribes on the phone and returns the text → the Shortcut copies it only if there is text → the user picks any field and pastes.

## Decisions

### One App Intent in the app process: `ToggleDictationIntent: AudioRecordingIntent`

- `AudioRecordingIntent` (iOS 18+) is the system protocol for an intent that starts audio recording without bringing the app to the foreground. The metadata extracted at build time confirms the intent carries the `AudioRecording` system protocol and `openAppWhenRun = false`.
- Apple's documentation for `AudioRecordingIntent` requires the app to start a Live Activity when recording begins and keep it while recording; otherwise the system may stop the recording. The prototype therefore refuses to start (outcome `failed.liveActivityUnavailable`) when Live Activities are off, instead of recording audio it may lose. Whether that refusal is necessary when the app happens to be in the foreground is a device question (see below).
- The intent lives in the **app target, not an App Intents extension**: the microphone session, the loaded model and the state must survive from the first invocation to the second, so both have to run in the same process. The first invocation returns `started` as soon as the microphone is running; the Shortcut does not wait during dictation.
- The intent does not set `openAppWhenRun` or `supportedModes`, so it asks for background execution (the default). If a device shows that iOS forces the app to the foreground, iOS 26's `supportedModes = [.background, .foreground(.dynamic)]` with `continueInForeground(_:)` is the documented escape hatch; that must be recorded as a limitation, not hidden.
- iOS 27 adds `allowedExecutionTargets`; the default (main app) is what we want and is left alone.

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

- **Session: `.playAndRecord`, mode `.default`, options `.mixWithOthers` + `.allowBluetoothHFP`** (`DictationSessionConfiguration.dictation`), category and mode set before `setActive(true)` on every start, deactivated (`notifyOthersOnDeactivation`) the moment capture stops. `UIBackgroundModes` contains `audio`, which is what lets an active recording continue in the background; once the session is inactive the app is an ordinary background app again. There is no silent playback and no dummy recording.
  - *Why mixable.* The first device run used `.record`, which cannot be mixable, and an Action Button start with Sorla in the background failed at activation with `NSOSStatusErrorDomain 560557684` (`'!int'`, `AVAudioSession.ErrorCode.cannotInterruptOthers`). Apple documents that code as “an attempt to make a nonmixable audio session active while the app was in the background”. A background app may only activate a mixable session, so the category moved to `.playAndRecord` (the recording category that accepts `.mixWithOthers`). Sorla plays nothing, so the playback half and `.defaultToSpeaker` are unused. The Live Activity is still started before the session, as `AudioRecordingIntent` requires (“you must start a Live Activity when you begin the audio recording … If you don't start a Live Activity, the audio recording stops”).
  - *What it costs.* Other audio (music, a podcast) keeps playing during dictation instead of being paused, and the microphone can pick it up. `.duckOthers` (also mixable) is the obvious next step if that matters; it was left out to keep the change minimal.
  - *What may still go wrong.* Apple also documents `cannotStartRecording` (`'!rec'`) as what “usually occurs when an app starts a mixable recording from the background”, and a forum answer (not from Apple staff) claims recording can't start from the background at all, even through an intent. `AudioRecordingIntent` exists to allow exactly this start, so the device test decides. If activation now fails with `'!rec'` or the capture is silent, the `diagnostic.session`/`diagnostic.audioStart` rows say so, and the fallback is `supportedModes` with `.foreground(.dynamic)` (see above).
- Capture uses the Mac's `AudioRecorder` and `EngineAudioInput` (AVAudioEngine tap) unchanged, but **every recording gets a new `AVAudioEngine`** (`FreshEngineAudioInput`), made only after the session is configured and active. Its input format is read after activation, and the tap is installed with that format. On the first device run the one engine made at launch, before the category allowed input, was reused, and the first capture after launch came back as nothing but zeros (peak `-inf` dBFS); a later one in the same process worked. Audio stays in memory and is dropped as soon as it has been transcribed, cancelled or found empty.
- **Restart instead of zeros.** If the whole first second is below −90 dBFS, the recorder drops it and starts over on a new engine. After an engine configuration change (route or format), it starts over if nothing has been heard yet. Otherwise it carries on at the same rate on a new engine; if the rate changed, capture ends and keeps what was heard. An input route that appears only after activation, with nothing heard yet, also starts over. There are at most three restarts per recording, each logged as `diagnostic.audioRestart`.
- A call, Siri or a media-services reset **ends capture but keeps what was heard**; the Live Activity changes to “Stopped — trigger again to transcribe” and the next trigger transcribes it. The next start sets the session up and builds an engine from scratch. The microphone is never left open waiting for the user.
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

**iOS 18.0**, the minimum for `AudioRecordingIntent`. Everything else used (`TransientAppEntity`, `LiveActivityIntent`, `AVAudioApplication`, ActivityKit) is available there. Recommendation: keep 18.0 for the feasibility builds so an older test phone (e.g. iPhone 13) can be included, and decide the shipping minimum from #65: supported iPhones will be limited by memory and Neural Engine speed long before the OS version matters. If the device tests need iOS 26 API (`supportedModes`), raise the target to 26 rather than branching.

## State model

All state lives on the main actor in `DictationCoordinator`, so triggers are handled one at a time.

| Phase | Trigger (toggle) | Cancel (Live Activity button) | Capture ends by itself (limit, call, route) |
|---|---|---|---|
| idle | checks → start → `Started`; or `Failed(…)` without touching the microphone | nothing to cancel | ignored |
| listening | stop microphone → transcribing | discard audio → `Cancelled` | stop microphone, keep audio → captured |
| captured | transcribe the kept audio | discard audio → `Cancelled` | — |
| transcribing | `Busy` (the running one keeps its result) | the pending trigger returns `Cancelled`; late text dropped | — |

Start checks, in order: a leftover **session marker** (a timestamp in `UserDefaults`, written at start and cleared at every end) means the process that was recording died — system termination or force-quit — so the trigger reports `failed.sessionLost` and ends any stale Live Activity instead of starting a new recording by surprise; then microphone permission (`failed.microphoneNotAuthorized`; the prompt can only be shown in the app); then an installed model (`failed.modelMissing`, so no words are recorded that can't be transcribed); then the Live Activity; then the microphone.

A transcription ends in exactly one of: `Transcribed(text)`, `Nothing Heard` (too short, or whitespace-only text), `Failed(silentInput | transcriptionFailed | timedOut | backgroundTimeExpired)`, `Cancelled`.

Unit tests (`iOS/Tests/DictationCoordinatorTests.swift`, no sleeps — fakes resume on command) cover: prompt start, preload, each refused start, stop-before-transcribe, empty/short audio, silent input (zeros and below −90 dBFS) as `failed.silentInput`, failure, timeout, background expiry, busy during transcription, consecutive dictations, cancel while listening/captured/transcribing, late result after cancel not leaking into the next dictation, limit and interruption keeping audio, lost session, the session and audio diagnostic rows, and metrics never containing text. `iOS/Tests/LiveDictationRecorderTests.swift` drives the real recorder with a fake session and a fake microphone. It covers the mixable configuration, configure → activate → engine order, a refused activation never opening the microphone, a new engine per recording, restarting after a silent first second (bounded), configuration changes (start over, carry on, or end capture), interruptions, media-services reset and the background row.

## Privacy

No audio is written anywhere. Transcript text exists only in memory until it is returned to the Shortcut. The diagnostics log (`Dictation` tab, `os_log` category `Dictation`) records outcome names, timings, audio length and background time left — never text. Its `diagnostic.*` rows are numbers and system names only:

| Row | When | Content |
|---|---|---|
| `diagnostic.session` | every start, also a failed one | category, mode, options, route input port (`none` if empty), session sample rate, input channels |
| `diagnostic.audioStart` | the microphone didn't start | the system error (e.g. `560557684`) |
| `diagnostic.audioRestart` | the recorder started over or carried on on a new engine, or media services were reset | reason and result |
| `diagnostic.background` | Sorla went to the background while listening | seconds listened so far, peak level so far |
| `diagnostic.audio` | every stop | samples, peak and RMS dBFS, where there was sound (`sound 0.4–9.1 s of 9.2 s` or `no sound in …`), seconds listened |
| `diagnostic.liveActivity` | the Live Activity was refused | the system's reason | Network use is limited to the model download from Hugging Face.

## Known restrictions and risks

- **Unverified on device.** Background start via `AudioRecordingIntent`, its Live Activity requirement, how long the second invocation may run, and clipboard behaviour on a locked phone are all device questions.
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

**Audio (the fixes from the first device run)**
- [ ] Action Button with Sorla in the background (another app in front, and from the Home Screen): `started`, no `diagnostic.audioStart`, the `diagnostic.session` row shows `playAndRecord`, `mixWithOthers+allowBluetoothHFP`, an input port and a sample rate; the dictation then transcribes correctly. Note any `'!rec'`/`560557684` error.
- [ ] First dictation after a fresh launch (force-quit, open Sorla, dictate from the app or the Action Button): real text, `diagnostic.audio` shows a peak well above −90 dBFS. Note any `diagnostic.audioRestart` row.
- [ ] Start in the foreground, go to the Home Screen after ~5 s, speak on for ~15 s, stop with the Action Button: the text covers the whole dictation; `diagnostic.background` shows the time you left, and `diagnostic.audio`'s sound range reaches the end of the recording.
- [ ] Music playing in another app, then dictate: record whether the music keeps playing (expected with `mixWithOthers`) and whether it disturbs the text.
- [ ] Covering the microphone is not silence (the input still has noise), so it must not give `failed.silentInput`; that outcome should only appear when iOS delivers nothing. Record every `failed.silentInput` together with the rows before it.

**Triggers and interruptions**
- [ ] Two presses in quick succession (< 0.5 s); press during transcription → `Busy`, the first result is still copied exactly once.
- [ ] Cancel from the Live Activity (Lock Screen and Dynamic Island) while listening → nothing copied.
- [ ] Incoming phone call / FaceTime / Siri while listening → capture stops, Live Activity says “Stopped”; next press transcribes what was said before.
- [ ] Headset route change while listening (connect/disconnect AirPods, plug/unplug wired) → capture carries on (`diagnostic.audioRestart: configuration change, continued on a new engine`), or, if the new input runs at another rate, stops like an interruption and the next press transcribes what was said. Also dictate *through* AirPods.
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

Open. Go requires the journey to work without bringing Sorla to the foreground (or a precisely documented, acceptable exception), no clipboard writes outside successful non-empty results, no indefinite listening, and stop→copied within the budget agreed after #65.
