# Sorla for iPhone — feasibility prototype

This folder holds the iPhone feasibility work for the milestone **Sorla iOS — First TestFlight**:

- **#65** — a benchmark harness that installs the published Pianissimo model the same way Sorla for Mac does and measures storage, memory, compile/load time and stop-to-text latency. See [Docs/benchmark.md](Docs/benchmark.md).
- **#66** — an Action Button / Back Tap prototype: one App Intent, “Diktera med Sorla”, that starts listening on the first run and stops, transcribes on the phone and returns the text on the next. See [Docs/action-button.md](Docs/action-button.md).

It is a prototype, not the production app (#67–#69). Nothing here changes Sorla for Mac: the Mac package (`Package.swift`, `Sources/`) is untouched, and the prototype compiles a few platform-neutral files from `Sources/SorlaCore` read-only (listed in `project.yml`). Code duplicated for now is marked with a comment pointing at #67.

## Layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen spec. The generated `SorlaiOS.xcodeproj` is never committed. |
| `Sorla/Dictation` | The toggle's state model (`DictationCoordinator`) and its iOS wiring. |
| `Sorla/Intents` | `ToggleDictationIntent`, its result entity and the App Shortcut. |
| `Sorla/Benchmark` | Model install measurement, memory probe, benchmark runner and report. |
| `Sorla/App` | The three-tab setup/diagnostics UI (Dictation, Model, Benchmark). |
| `Shared` | Live Activity attributes and the cancel intent, compiled into the app and the extension. |
| `LiveActivity` | The widget extension that shows the Live Activity while dictating. |
| `Tests` | Unit tests (state model, result/clipboard rule, report, memory probe). |
| `Benchmark/make-utterances.sh` | Generates synthetic Swedish test clips into `Benchmark/Utterances/` (git-ignored). |

## Build and test (simulator only)

Requires Xcode 27 and XcodeGen (`brew install xcodegen`).

```sh
iOS/Benchmark/make-utterances.sh          # optional: bundles 5/10/30/60/120 s test clips
xcodegen generate --spec iOS/project.yml
xcodebuild -project iOS/SorlaiOS.xcodeproj -scheme Sorla \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project iOS/SorlaiOS.xcodeproj -scheme Sorla \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test CODE_SIGNING_ALLOWED=NO
```

If several simulators share the name, add `,OS=<version>` to the destination.

## Identifiers and signing

The bundle identifiers are placeholders (`com.sorla.ios`, `com.sorla.ios.LiveActivity`) and no team is set. Real identifiers, signing, entitlements and the privacy manifest are decided in #70. To run on a device before then, set a team locally in Xcode and don't commit it.
