# Pianissimo on iPhone — benchmark procedure and results (#65)

**Status:** harness implemented and exercised end to end in the iOS Simulator only. **No physical-device measurements exist yet**, so there is no evidence for supported iPhones, memory policy or latency on a phone. Every device in the results table below is *untested* until a row is filled in from a physical run.

## What the harness measures

The app (`iOS/`, see `iOS/README.md`) has a **Model** tab and a **Benchmark** tab. Both produce Markdown reports shown on screen, copyable, and saved to `Documents/Reports/` (reachable through Finder or the Files app).

| Measure | How |
|---|---|
| Download vs installed storage | The model is installed exactly as Sorla for Mac installs it: `ModelInstaller` fetches `manifest.json` from `markstrom/pianissimo-sv-coreml`, downloads each file, verifies size and SHA-256, compiles every `.mlpackage` on the device, runs the self-test, then `ModelSwap` installs it. The report gives the manifest total, the downloaded packages on disk and the installed compiled model (logical and allocated bytes). |
| Fresh compile | Time and peak memory of each `MLModel.compileModel` call during install. The downloaded packages are kept, so **Reinstall** re-measures a fresh compile without downloading again. |
| First (cold) load | The install self-test: first load of the compiled model plus 1 s of silence, time and peak. |
| Load in a new process / cached load | Benchmark: *Load, first in this process* (after a force-quit this is the cold-process load from the OS cache), then *Reload after cleanup, same process*. The report states process uptime and whether it was the first load in the process. |
| First inference | 1 s of silence right after loading, as the app's warm-up does. |
| Stop-to-result latency | For each clip and run: resampling the clip's audio to 16 kHz plus transcription, i.e. from “audio in hand” to text. Median, p90 and max per clip, and every run. |
| Memory | `phys_footprint` (what iOS compares against the app's memory limit): baseline without model, model loaded, peak during load and during each transcription (sampled every 5 ms), after cleanup, and the process's lifetime peak. Also resident size with mapped weights, and `os_proc_available_memory()` headroom (0 in the simulator). |
| Conditions | Device model identifier, iOS version, build configuration, app version, model version and source revision, FluidAudio version and revision, thermal state at start and end (and per run), battery level/state, Low Power Mode, VoiceOver, network (online/offline). |

The dictation prototype (#66) additionally logs real trigger→listening and stop→result times for Action Button use; see `action-button.md`.

Model under test: `pianissimo-sv` 1.0.0 from Hugging Face `markstrom/pianissimo-sv-coreml` (repository revision `106fa163a138` at the time of writing; source `KlangAI/pianissimo-sv@8f1f6d8f8bd7`), FastConformer encoder with int8 weights (per the model card), 688 MB published. Dependency: FluidAudio **0.16.1** (`b811a61569aa02691c99b808d08ee989b630c133`), pinned with `exactVersion` in `project.yml`, identical to the Mac app's `Package.resolved`.

## Reproducible procedure on a physical iPhone

### Prepare (Mac)

1. Check out the commit to test; note its hash.
2. `iOS/Benchmark/make-utterances.sh` — writes `sv-005s`, `sv-010s`, `sv-030s`, `sv-060s`, `sv-120s` (synthetic Swedish, voice Alva, 48 kHz) to `iOS/Benchmark/Utterances/`. 120 s is the prototype's proposed maximum dictation length.
3. `xcodegen generate --spec iOS/project.yml`, open `iOS/SorlaiOS.xcodeproj`, set a signing team locally (not committed; real signing is #70), and set **Run → Build Configuration → Release** in the scheme. Never report Debug numbers.
4. Optional real speech: record the same five lengths of natural Swedish (a few people if possible), and copy them as WAV/M4A into the app's `Documents/Utterances` via Finder (iPhone → Files → Sorla) after installing. Real speech is required before drawing accuracy conclusions; synthetic speech is fine for timing and memory.

### Prepare (iPhone)

- Battery above 50 %, record whether charging. Low Power Mode off (unless testing it). Close other apps. Let the phone cool until the thermal state is *nominal* (the report shows it).
- Note the storage free before install (Settings → General → iPhone Storage).

### Run

For every device, in this order, copying each report into the results file (or collecting them from `Documents/Reports`):

1. **Install** — Model tab → *Download and Install* on Wi-Fi. Record the install report. Then Settings → General → iPhone Storage → Sorla for the system's view of app size.
2. **Fresh compile, repeated** — *Reinstall* twice more (downloads are reused). Record all three.
3. **Cold process** — force-quit Sorla (app switcher), wait 10 s, open it, Benchmark tab, runs per clip **5**, *Run Benchmark*. This is the ordinary case.
4. **Warm process** — run the benchmark again without quitting.
5. **Offline** — enable Airplane Mode (after install), force-quit, reopen, run. Confirms nothing needs the network and records `Network: offline`.
6. **VoiceOver** — turn VoiceOver on, force-quit, reopen, run.
7. **Sustained / thermal** — runs per clip 20 with only `sv-060s` (move other clips out of the folder, or temporarily delete them from the bundle before building) or run the benchmark 5× back to back; record thermal state per run and the slowest runs. Note battery percentage before and after.
8. **Memory pressure** — open the Camera and a large game, return to Sorla and run; note whether iOS terminated Sorla at any point (it will restart from the launch screen).
9. **Real speech** — repeat step 3 with the recorded clips in `Documents/Utterances`.
10. Repeat 3–9 on each candidate device. Include an older phone (iPhone 13-class) if one is available; list devices you could not test as *untested*.

Hands-free alternative: pass the launch argument `-SorlaAutoBenchmark YES` (Xcode scheme → Arguments) to install if needed and run once with the default 3 runs per clip; the report is saved to `Documents/Reports`.

### What to report back in #65

Paste the summary rows into the results table below and attach the full reports. Keep ordinary and slow cases: medians **and** p90/max, the warm-up/first-load times, and the thermal-throttled runs. Mark estimates as estimates.

## Results table template

One row per device × case. Units: ms for latency, s for loads, decimal MB for memory and storage.

| Date | Device (identifier) | iOS | Build (commit, config) | Model (version, source rev, precision) | FluidAudio (rev) | Conditions (thermal start→end, battery, LPM, VoiceOver, network) | Case | Audio (s) | Runs | Median | p90 | Max | Peak footprint (MB) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | pianissimo-sv 1.0.0, 8f1f6d8f8bd7, int8 enc | 0.16.1 (b811a61) | | Stop→text | 10 | | | | | | |

Storage and load rows use the same columns with *Case* = `Download size`, `Installed size`, `Compile (all packages)`, `First load (self-test)`, `Load, new process`, `Reload, same process`, `Baseline memory`, `Model loaded memory`, `After cleanup memory`.

### Devices

| Device | Status |
|---|---|
| iPhone 16-class (e.g. iPhone 16 / 16 Pro) | untested |
| iPhone 15 Pro | untested |
| iPhone 13 (older candidate) | untested |
| Other | untested |

## Budget

The manifesto's budget is **under 0.5 s from letting go to seeing the text, for 10 s of speech**. The harness evaluates it for clips of 8–12 s and reports *met (every run)*, *median met, slow runs miss*, or *missed*. The benchmark's figure excludes microphone shutdown and, on iOS, the Shortcut's own overhead and the manual paste, so the Action Button journey's stop→copied time (from `action-button.md`) must be reported against the same budget separately. No iOS-specific budget is proposed yet; if device results require one, it will be written down explicitly here and in MANIFESTO.md (#70) rather than applied silently.

## Simulator-only numbers — not evidence

The runs below come from the iOS Simulator on a Mac. Core ML in the Simulator runs on the Mac's CPU without the Neural Engine, memory limits don't apply and the Mac's RAM and thermal behaviour are not a phone's. They show only that the harness installs, loads and transcribes correctly on the iOS SDK. **Do not quote them as iPhone performance.**

Run on 2026-09-25: simulated iPhone 17 Pro (`iPhone18,1`), iOS 26.5 Simulator runtime, Xcode 27.0, host Mac with Apple silicon, Release build of this prototype, pianissimo-sv 1.0.0, FluidAudio 0.16.1, online, 3 runs per clip, synthetic clips from `make-utterances.sh`.

| Case (Simulator) | Value |
|---|---|
| Published download (manifest total) | 688 MB, 15 files, 22.7 s on the host's connection |
| Downloaded packages / installed compiled model on disk | 688 MB / 689 MB |
| Compile, all four packages | 0.45 s (Encoder 0.28 s) |
| Self-test (first load + 1 s silence) after install | 5.64 s |
| Load, first in a new process / reload in the same process | 3.87 s / 0.16 s |
| First inference (1 s silence) | 1.48 s |
| Stop→text median (max), 5.1 s clip | 1344 ms (1424) |
| Stop→text median (max), 10.0 s clip | 1476 ms (1639) |
| Stop→text median (max), 30.2 s clip | 3266 ms (3383) |
| Stop→text median (max), 59.9 s clip | 4902 ms (4929) |
| Stop→text median (max), 120.8 s clip | 7985 ms (8036) |
| phys_footprint: baseline / model loaded / peak transcribing / after cleanup | 69 / 79 / 211 / 76 MB |
| Resident incl. mapped weights, model loaded | 221 MB |

The small `phys_footprint` with the model loaded is expected here: Core ML maps the weights from the compiled files, and clean file-backed pages aren't counted in `phys_footprint`. How much the Neural Engine path adds on a phone is one of the things only a device run can show.

## Open questions for the go/no-go

- Does the model load and run on the Neural Engine on each candidate phone, and how long is the first (specialising) load after install?
- `phys_footprint` with the model loaded and during a 60–120 s transcription vs the device's limit (`os_proc_available_memory`), and whether a backgrounded Sorla holding the model is terminated in normal use. That decides the loading policy: keep loaded, unload after each dictation, or unload on background.
- Stop→text for 10 s of speech against the 0.5 s budget, including slow runs and a warm phone.
- Storage: ~0.69 GB download plus a compiled copy of about the same size; whether to delete the downloaded packages after install (the Mac does), which halves the footprint at the cost of re-downloading on update.
