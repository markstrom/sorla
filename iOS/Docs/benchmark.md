# Pianissimo on iPhone — benchmark procedure and results (#65)

**Status:** harness implemented and exercised in the iOS Simulator; first physical-device measurements (model load per compute unit, iPhone 16 Plus) are in *Device results* below. Other devices remain *untested*.

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
| iPhone 16-class (e.g. iPhone 16 / 16 Pro) | iPhone 16 Plus: model load per compute unit measured (Device results); full benchmark untested |
| iPhone 15 Pro | untested |
| iPhone 13 (older candidate) | untested |
| Other | untested |

## Budget

The manifesto's budget is **under 0.5 s from letting go to seeing the text, for 10 s of speech**. The harness evaluates it for clips of 8–12 s and reports *met (every run)*, *median met, slow runs miss*, or *missed*. The benchmark's figure excludes microphone shutdown and, on iOS, the Shortcut's own overhead and the manual paste, so the Action Button journey's stop→copied time (from `action-button.md`) must be reported against the same budget separately. No iOS-specific budget is proposed yet; if device results require one, it will be written down explicitly here and in MANIFESTO.md (#70) rather than applied silently.

## Device results: model load and compute units (iPhone 16 Plus, 2026-09-26)

iPhone 16 Plus (`iPhone17,4`), iOS 27.0, Release build of `ios/feasibility`, pianissimo-sv 1.0.0 (int8 encoder), FluidAudio 0.16.1, thermal *nominal* throughout, Low Power Mode off. Measured with `-SorlaLoadProbe <units>` (`DeviceProbes.swift`): each launch is a fresh process that loads the four compiled components itself with the given compute units (the preprocessor is always CPU, as in FluidAudio), runs 1 s of silence, transcribes the bundled 10 s and 30 s clips twice, cleans up, loads again in the same process, writes a report and exits. Stop→text here excludes resampling (a few ms). One or three runs per variant, in the order listed; **the phone ran out of storage during the session** (see below), which may have affected the failed rows and the slow first ANE run.

| Compute units (encoder, decoder, joint) | Cold load, fresh process: total (encoder) s | Warm reload, same process s | First inference ms | Stop→text 10 s ms (run 1 / 2) | Stop→text 30 s ms | Loaded, idle footprint MB | Peak MB |
|---|---|---|---|---|---|---|---|
| `.cpuAndNeuralEngine` (current default) run 1 | 54.7 (54.4) | 27.9 | 1636 | 1328 / 877 | 2449 / 2360 | 1994 | 2293 |
| `.cpuAndNeuralEngine` run 2 | 13.7 (13.3) | 11.6 | 1214 | 873 / 617 | 1624 / 1603 | 2001 | 2279 |
| `.cpuAndNeuralEngine` run 3 | 11.4 (11.0) | 11.3 | 823 | 485 / 509 | 1517 / 1527 | 2033 | 2263 |
| `.cpuAndNeuralEngine` + `specializationStrategy = .fastPrediction` | 10.0 (9.7) | 10.7 | 585 | 526 / 587 | 1612 / 1732 | 1864 | 2275 |
| `.all` | 16.5 (16.1) | failed (Core ML error 0) | 4434 | 468 / 442 | 1386 / 1453 | 1976 | 2264 |
| `.cpuAndGPU` | — process exited (code 1) after 11 s, no report | — | — | — | — | — | — |
| **`.cpuOnly` run 1** | **5.8 (5.7)** | **4.4** | 1232 | 563 / 539 | 1710 / 1817 | 2019 | 2260 |
| **`.cpuOnly` run 2** | **4.4 (4.2)** | **4.1** | 848 | 494 / 578 | 1506 / 1583 | 1990 | 2276 |
| **`.cpuOnly` run 3** | **4.3 (4.1)** | **4.3** | 601 | 537 / 580 | 1681 / 1732 | 1975 | 2260 |

Findings:

- **The encoder is the whole load.** Preprocessor, decoder and joint load in 0.00–0.19 s each in every variant.
- **The Neural Engine compile is not reused.** A second load in the same process takes as long as the first (11–28 s), and a fresh process never loads faster than ~10 s. FluidAudio 0.16.1's `AsrModels.loadLocal` does nothing unusual: it opens the already compiled `.mlmodelc` with `MLModel(contentsOf:configuration:)` (no `.mlpackage` compile at load; note it builds a new `MLModelConfiguration` per component and copies only the compute units and `allowLowPrecisionAccumulationOnGPU`, so hints set on the passed configuration never reach Core ML). The time is Core ML specialising the encoder for the device each time. `.fastPrediction` changes little. The iOS 27 SDK has no new model-caching API (`MLModelConfiguration`/`MLOptimizationHints` are unchanged since iOS 18).
- **Core ML's cache folder `Library/Caches/com.sorla.ios/com.apple.e5rt.e5bundlecache` grows without helping**: 31 files / 1654 MB at the first probe, 44 files / 2349 MB at the end of the session, with new hash-named entries and existing files rewritten on many loads. By the end the phone had **0 bytes free** (a UIKit state save failed with ENOSPC and a reinstall failed: 41 MB needed, 3.8 MB purgeable). Whether this folder alone filled the phone is not established, but it is 2.3 GB for a 688 MB model and is not being purged by iOS.
- **The CPU loads the model in ~4–6 s, cold or warm**, 2–10× faster than the Neural Engine, and transcribes 10 s of speech in 0.49–0.58 s (ANE: 0.49–1.33 s in the same session, 0.44–0.47 s with `.all`). Memory is the same in every variant: ~2.0 GB while loaded, ~2.26–2.29 GB peak while loading, and 0.73–0.88 GB still resident after `cleanup()`.
- **Keeping the model loaded is not viable** in the background: ~2.0 GB idle footprint is far above what iOS lets a suspended app keep; it would be the first process terminated under memory pressure. (A background-survival run was prepared, `-SorlaIdleProbe YES`, but the phone's time ran out before it could be run.)
- `.cpuAndGPU` is ruled out regardless: iOS refuses GPU work from the background, where the Action Button stop runs.

**Recommendation (implemented):** run every component on the CPU on the iPhone (`PhoneTranscriptionEngine`, `PhoneModelConfiguration`). With the preload already starting at the start press, even a cold first dictation after Sorla was closed needs about 4–6 s load + 0.6–1.2 s first inference + 0.5–1.8 s transcription, i.e. **6–9 s, inside the ~27 s of background time** a stop gets, whereas the Neural Engine's 10–55 s does not reliably fit. Not yet measured: energy per dictation on the CPU (likely higher than the ANE), and the full Action Button journey with this build (see `action-button.md`). Stop→text for 10 s is at or slightly above the 0.5 s budget on both CPU and ANE.

### Silent input on a fresh launch (#66)

`-SorlaMicProbe 4` records once through `LiveDictationRecorder` right after a fresh launch, once the app is active: 5 of 5 fresh launches captured real input (peak −20.8 to −24.0 dBFS, every 0.5 s window between −22 and −37 dBFS, sound from 0.0 s), 3 of them with a Neural Engine model load running at the same time, 2 without, so a concurrent load is not the cause. Activating the non-mixable `.record` session took 1.1–1.3 s while other audio was playing (`isOtherAudioPlaying` true). The all-zero case was not reproduced through a plain launch; it has only been seen on the intent's foreground-start path. The silent-start restart now makes a **new engine** instead of starting the same one again, the one change the earlier failed restart had not tried.

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
