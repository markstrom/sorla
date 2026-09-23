# Sorla v1 Settings, Indicator, Clipboard, Login Item — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Each task is dispatched from its own brief; this plan states requirements and interfaces, implementers write the code (TDD where a test is listed).

**Goal:** Deliver spec §14: settings window (trigger + mode + model + keep clipboard + launch at login), recording indicator with live waveform, clipboard restore after paste, launch at login.

**Spec:** [docs/superpowers/specs/2026-09-23-sorla-design.md](../specs/2026-09-23-sorla-design.md) §13–§14.

**Existing code (branch `walking-skeleton`):** `SorlaCore` — `AudioRecorder`, `ParakeetTranscriptionEngine` (actor, `SpeechModel`-selected), `RecordingController` (`@MainActor`, 150 ms tail, `cancelRecording()`, `setEngine(_:name:)`, os.Logger), `PasteService`, `PermissionsManager`, `PushToTalkGesture` (pure state machine), `RightCommandKeyMonitor` (NSEvent monitors), `SpeechModel`. `Sorla` — `AppDelegate` (status item menu with model picker, `UserDefaults` key `selectedModel`), `main.swift`.

## Global Constraints

- Swift tools-version 5.10 (Swift 5 mode), macOS 14 floor, Apple Silicon.
- Code from scratch; no comments by default (at most one short why-line); no multi-line doc comments; no comments referring to tasks/plan/reviews; no attribution references to other projects in source; no `@preconcurrency`/`@unchecked`.
- `swift build` and `swift test` produce no warnings from `Sources/`/`Tests/`.
- Tests never touch the system clipboard (`NSPasteboard.general`), real `UserDefaults.standard`, the microphone, Application Support, or launch the app. Use `NSPasteboard.withUniqueName()`, `UserDefaults(suiteName:)` with a unique name (removed in tearDown), temp dirs.
- Implementers never run `Scripts/build-app.sh`, never launch/kill the app, never touch `~/Library/Application Support/Sorla` or `.../FluidAudio` (a model conversion writes there concurrently).
- Commit on `walking-skeleton`, trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, no push.
- UI strings in English (as the existing menu).

---

### Task 13: Keep clipboard content

**Files:** `Sources/SorlaCore/PasteService.swift`, `Sources/SorlaCore/RecordingController.swift`, `Sources/Sorla/AppDelegate.swift` (wire default), `Tests/SorlaCoreTests/PasteServiceTests.swift`.

**Requirements:**
- `PasteService` gains `static func snapshot(of pasteboard: NSPasteboard = .general) -> PasteboardSnapshot` and `static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard = .general)`; `PasteboardSnapshot` is a value type holding every item's (type → data) pairs, preserving item boundaries and order; an empty pasteboard round-trips to empty.
- `writeToPasteboard` returns the pasteboard's `changeCount` after writing.
- `RecordingController` gets `public var keepClipboardContent = true`. On a successful dictation with `keepClipboardContent`: snapshot **before** writing the transcript; write; paste; if `AXIsProcessTrusted()` was true, wait 0.5 s, then restore the snapshot **only if** the pasteboard's `changeCount` still equals the value returned by the write. If paste couldn't be delivered (not trusted), leave the transcript on the clipboard. Log `clipboard restored` / `clipboard kept (reason)` at info.
- The restore decision is a pure, tested function: `static func shouldRestoreClipboard(keepSetting: Bool, pasteDelivered: Bool, changeCountAfterWrite: Int, currentChangeCount: Int) -> Bool`.
- `AppDelegate`: nothing to change beyond keeping the default (settings UI comes in Task 15).

**Tests (TDD):** snapshot/restore round-trip with two items including non-string data (e.g. PNG bytes under `.png`, a string under `.string`) on a unique pasteboard; empty round-trip; `shouldRestoreClipboard` truth table (keep off → false; not delivered → false; changeCount changed → false; all good → true).

---

### Task 14: Settings store, trigger keys, toggle mode

**Files:** create `Sources/SorlaCore/AppSettings.swift`, `Sources/SorlaCore/TriggerKey.swift`, `Sources/SorlaCore/TriggerMonitor.swift` (replaces `RightCommandKeyMonitor.swift`, delete it); modify `PushToTalkGesture.swift`, `AppDelegate.swift`, `Package.swift` (re-add `KeyboardShortcuts` from `3.1.0` for custom combos); tests `PushToTalkGestureTests.swift`, `TriggerKeyTests.swift`, `AppSettingsTests.swift`.

**Requirements:**
- `public enum TriggerKey: String, CaseIterable` — `rightCommand` (default), `rightOption`, `rightControl`, `fn`, `customShortcut`. For the four modifier cases expose `keyCode: UInt16` and `deviceMask: UInt` (right ⌘ 0x36/0x10, right ⌥ 0x3D/0x40, right ⌃ 0x3E/0x2000, Fn 0x3F/`NSEvent.ModifierFlags.function.rawValue`) — verify each against the macOS SDK headers (`Events.h` kVK_* and `IOLLEvent.h` NX_DEVICE* / NX_SECONDARYFNMASK) and cite them in the report; plus `displayName`.
- `public enum RecordingMode: String, CaseIterable` — `pushToTalk` (default), `toggle`; `displayName`.
- `PushToTalkGesture` takes a `mode`. Push-to-talk behavior unchanged. Toggle: a *clean tap* (trigger down then up with no `otherKeyDown` in between) toggles: idle → `.start`; recording → `.finish`, or `.cancel` if the recording lasted < `minimumHold` (0.3 s, measured from the start tap's down to the stop tap's up). `otherKeyDown` while the trigger is held makes that press not a tap (no action, recording state unchanged); `otherKeyDown` while not holding the trigger is ignored in toggle mode (it never cancels a toggle recording). Existing tests keep passing; add toggle tests.
- `@MainActor public final class AppSettings: ObservableObject` backed by an injected `UserDefaults` (default `.standard`): `@Published` `triggerKey`, `recordingMode`, `model` (`SpeechModel`, key stays `selectedModel`, falls back to `.parakeet` if Pianissimo isn't installed), `keepClipboardContent` (default true). Each write persists immediately; init reads persisted values with defaults.
- `TriggerMonitor` (`@MainActor`): `init(onStart:onFinish:onCancel:)`, `func configure(trigger: TriggerKey, mode: RecordingMode)` — for modifier triggers uses NSEvent global+local `.flagsChanged`/`.keyDown` monitors with the key's keyCode and device mask (same approach as today's RightCommandKeyMonitor); for `.customShortcut` uses `KeyboardShortcuts` name `.sorlaCustomTrigger` (no default combo) `onKeyDown`→triggerDown, `onKeyUp`→triggerUp. Reconfiguring tears down the previous monitors/handlers cleanly (use `KeyboardShortcuts.removeHandler(for:)` / disable) and resets the gesture; if a recording is active when reconfigured, cancel it via `onCancel` first.
- `AppDelegate` owns one `AppSettings` and one `TriggerMonitor`; observes settings (Combine `$triggerKey`, `$recordingMode`, `$model`, `$keepClipboardContent`) to reconfigure the monitor, switch engine (existing `setEngine` path) and set `recordingController.keepClipboardContent`. The menu's model picker reads/writes `AppSettings.model` so menu and (upcoming) settings window stay in sync.

**Tests (TDD):** toggle-mode gesture cases (tap starts; tap stops → finish; tap within 0.3 s → cancel; other key during held trigger → no toggle; other key while idle/recording not holding → ignored; push-to-talk regression suite unchanged); `TriggerKey` keyCode/mask table and raw values stable; `AppSettings` defaults, persistence round-trip through a unique `UserDefaults` suite, Pianissimo fallback when not installed (inject the installed check, e.g. `init(defaults:, isInstalled: (SpeechModel) -> Bool = { $0.isInstalled })`).

---

### Task 15: Settings window + launch at login

**Files:** create `Sources/Sorla/SettingsView.swift`, `Sources/Sorla/SettingsWindowController.swift`, `Sources/SorlaCore/LoginItem.swift`; modify `AppDelegate.swift`.

**Requirements:**
- Menu gets `Settings…` (key equivalent `,`) above the model section; opens (or re-focuses) one settings window; the app activates so the window comes to front, and returns to accessory behavior (no Dock icon) — use `NSApp.activate()` and keep `.accessory` policy.
- SwiftUI `Form`: Trigger (picker of `TriggerKey` display names; when `.customShortcut` show `KeyboardShortcuts.Recorder` for `.sorlaCustomTrigger`), Mode (segmented: Push to talk / Toggle), Model (picker; Pianissimo disabled with "not installed" when missing), Keep clipboard content (toggle), Launch at login (toggle).
- `LoginItem` wraps `SMAppService.mainApp`: `isEnabled` (status == `.enabled`), `setEnabled(_:) throws`; the toggle reflects the real status after each change and on window open; failures are logged and the toggle snaps back. `.requiresApproval` shows a short hint text with a button that opens Login Items settings (`SMAppService.openSystemSettingsLoginItems()`).
- All controls bind to the shared `AppSettings`; changes apply immediately (Task 14 wiring).

**Tests:** none for SwiftUI/SMAppService. Verification: clean build, full suite passes.

---

### Task 16: Recording indicator

**Files:** create `Sources/SorlaCore/AudioLevel.swift`, `Sources/Sorla/RecordingIndicator.swift` (panel + SwiftUI view); modify `AudioRecorder.swift` (level callback), `RecordingController.swift` (publish level + recording state), `AppDelegate.swift`; test `Tests/SorlaCoreTests/AudioLevelTests.swift`.

**Requirements:**
- `AudioLevel.normalized(rms:) -> Float` maps RMS to 0…1 on a dB scale (−50 dB → 0, 0 dB → 1, clamped); `AudioLevel.rms(_ samples: UnsafeBufferPointer<Float>) -> Float`. Pure and tested.
- `AudioRecorder` gets `public var onLevel: (@Sendable (Float) -> Void)?`, called from the tap with the normalized level of each buffer (keep the tap cheap: RMS only, no allocation beyond what exists).
- `RecordingController` forwards levels to the main actor and exposes `public var onLevel: ((Float) -> Void)?`.
- Indicator: `NSPanel` subclass, `.nonactivatingPanel` + borderless, `level = .statusBar`, `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, transparent background, rounded black capsule ~220×36 pt at the top centre of the screen containing the mouse (below the menu bar / notch area). Content: red record dot, SF Symbol `mic.fill`, and ~24 vertical bars showing the recent level history (newest right), smoothly updated. Shown on recording start, hidden on finish (at key release) and cancel. Never steals focus (the paste must land in the user's app).
- Respect Reduce Motion (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`): no bar animation, just update.

**Tests (TDD):** `AudioLevel` — silence → 0, full-scale sine (RMS ≈ 0.707, ≈ −3 dB) → ≈ 0.94, −50 dB and below → 0, above 0 dB clamps to 1, RMS of known buffers.
