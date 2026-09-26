# Sorla for iPhone — feasibility prototype

This folder holds the iPhone feasibility work for the milestone **Sorla iOS — First TestFlight**:

- **#65** — a benchmark harness that installs the published Pianissimo model the same way Sorla for Mac does and measures storage, memory, compile/load time and stop-to-text latency. See [Docs/benchmark.md](Docs/benchmark.md).
- **#66** — an Action Button / Back Tap prototype: one App Intent, “Diktera med Sorla”, that starts listening on the first run and stops, transcribes on the phone and returns the text on the next. See [Docs/action-button.md](Docs/action-button.md).

- **Sorla keyboard** (#66) — a minimal custom keyboard that inserts the finished transcript into the focused text field, so the person doesn't paste by hand. See [Docs/keyboard.md](Docs/keyboard.md).

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
| `Handoff` | The transcript and phase hand-off to the keyboard (Foundation only), compiled into the app and the keyboard. |
| `Keyboard` | The `SorlaKeyboard` keyboard extension (UIKit, no model, no audio). |
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

The bundle identifiers `com.sorla.ios` and `com.sorla.ios.LiveActivity` are registered to the team for device testing, and `project.yml` sets the team. The keyboard adds `com.sorla.ios.keyboard` and the App Group `group.com.sorla.ios` (on the app and the keyboard). App Groups are not in the public App Store Connect API, so provisioning with the API key can't create or assign the group (xcodebuild fails with "Authentication failed" and "doesn't support the group.com.sorla.ios App Group"). Once, in the Developer Portal (Certificates, Identifiers & Profiles): create the App Group `group.com.sorla.ios`, register `com.sorla.ios.keyboard`, and turn on App Groups with that group for both `com.sorla.ios` and `com.sorla.ios.keyboard` — or build once from Xcode signed in to the team, which does the same. After that the command below should only need to fetch profiles. The final identifiers, entitlements and privacy manifest for TestFlight are decided in #70.

Build and install from the command line with automatic provisioning through the App Store Connect API key (the key is passed by path, never committed):

```sh
xcodebuild -project iOS/SorlaiOS.xcodeproj -scheme Sorla -configuration Release \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -authenticationKeyPath <key.p8> -authenticationKeyID <key id> -authenticationKeyIssuerID <issuer> build
xcrun devicectl device install app --device <udid> <DerivedData>/Build/Products/Release-iphoneos/Sorla.app
```
