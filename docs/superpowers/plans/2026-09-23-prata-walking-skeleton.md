# Prata Walking Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the smallest possible end-to-end slice of Prata working: hold a hotkey, capture mic audio, transcribe it on-device with FluidAudio's Parakeet model, and paste the result at the cursor — so we can test whether it works and how fast it is, before building out the rest of the design.

**Architecture:** A menu-bar-only macOS app (no Dock icon) split into two Swift Package targets: `PrataCore` (a library holding all testable logic — audio capture/resampling, the transcription engine wrapper, paste handling) and `Prata` (a thin executable target with the AppKit entry point and menu bar UI, which is not unit-tested — it's verified by running the built app). No dictionary post-processing, no HUD, no settings window in this slice — those come after this is proven to work.

**Tech Stack:** Swift 5.10, Swift Package Manager, AppKit, AVFoundation, [FluidAudio](https://github.com/FluidInference/FluidAudio) (on-device ASR via CoreML/ANE), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (global hotkey).

**Spec:** [docs/superpowers/specs/2026-09-23-prata-design.md](../specs/2026-09-23-prata-design.md) — this plan implements §12 ("First build / walking skeleton") specifically, using the engine choice from §3.3 (FluidAudio + stock `parakeet-tdt-0.6b-v3-coreml`) and the paste mechanism from §6 (simplified: CGEvent Cmd+V only, no AppleScript fallback yet — see Task 7 for why).

## Global Constraints

- Platform floor: macOS 14 (Sonoma). Set via `platforms: [.macOS(.v14)]` in Package.swift and `LSMinimumSystemVersion` 14.0 in Info.plist.
- Swift tools version: 5.10.
- Dependencies pinned with `from:` floors: `FluidAudio` from `0.16.1`, `KeyboardShortcuts` from `3.1.0`.
- App is unsandboxed (not for Mac App Store distribution) — this avoids sandbox entitlement complexity for mic capture, global hotkeys, and synthetic paste events, none of which are compatible with the App Sandbox in the way this app needs them.
- Bundle identifier: `com.prata.app`. App name: `Prata` (per user instruction — matches the project directory name).
- No personal dictionary, no HUD, no settings window in this plan — see spec §12.
- Git commits use the repo's configured identity (`1905972+markstrom@users.noreply.github.com`, already set locally) and end with the `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` trailer.

---

## File Structure

```
Package.swift
Resources/
  Info.plist
Scripts/
  build-app.sh
Sources/
  PrataCore/
    PrataCore.swift            # placeholder doc comment, no logic
    AudioRecorder.swift        # mic capture + resampling to 16kHz mono
    TranscriptionEngine.swift  # protocol + ParakeetTranscriptionEngine
    PasteService.swift         # pasteboard write + CGEvent Cmd+V
    PermissionsManager.swift   # mic + accessibility permission checks
    HotkeyController.swift     # KeyboardShortcuts wiring, hold-to-record
    RecordingController.swift  # orchestrates the above, MainActor
  Prata/
    main.swift                 # NSApplication bootstrap (no @main App lifecycle)
    AppDelegate.swift           # NSStatusItem menu bar UI, wires RecordingController
Tests/
  PrataCoreTests/
    PermissionsManagerTests.swift
    AudioRecorderTests.swift
    PasteServiceTests.swift
```

`PrataCore` holds everything with real logic to test. `Prata` is deliberately thin — AppKit UI wiring that's verified by running the app, not by unit tests.

---

### Task 1: Project scaffold and app bundle packaging

**Files:**
- Create: `Package.swift`
- Create: `Sources/PrataCore/PrataCore.swift` (placeholder so the target isn't empty)
- Create: `Sources/Prata/main.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`

**Interfaces:**
- Produces: a `PrataCore` library target and a `Prata` executable target that later tasks add files to. A `Prata.app` bundle buildable via `Scripts/build-app.sh`.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Prata",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.16.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "PrataCore",
            dependencies: [
                "FluidAudio",
                "KeyboardShortcuts",
            ],
            path: "Sources/PrataCore"
        ),
        .executableTarget(
            name: "Prata",
            dependencies: ["PrataCore"],
            path: "Sources/Prata"
        ),
        .testTarget(
            name: "PrataCoreTests",
            dependencies: ["PrataCore"],
            path: "Tests/PrataCoreTests"
        ),
    ]
)
```

- [ ] **Step 2: Create a placeholder file so `PrataCore` isn't an empty target**

`Sources/PrataCore/PrataCore.swift`:

```swift
// PrataCore: shared logic for the Prata dictation app.
// Individual files (AudioRecorder, TranscriptionEngine, PasteService,
// PermissionsManager, HotkeyController, RecordingController) are added
// by later tasks.
```

- [ ] **Step 3: Create the executable entry point**

`Sources/Prata/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()
```

(No `AppDelegate` yet — that's Task 2. This just proves the target builds and launches.)

- [ ] **Step 4: Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Prata</string>
    <key>CFBundleDisplayName</key>
    <string>Prata</string>
    <key>CFBundleIdentifier</key>
    <string>com.prata.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>Prata</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Prata behöver mikrofonåtkomst för att transkribera din röst till text.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 5: Create `Scripts/build-app.sh`**

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP_NAME="Prata.app"
APP_DIR=".build/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/Prata "$APP_DIR/Contents/MacOS/Prata"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
```

- [ ] **Step 6: Make the script executable and build**

```bash
chmod +x Scripts/build-app.sh
swift build
```

Expected: builds with no errors (two targets, one empty-ish, one test target with no tests yet — that's fine).

- [ ] **Step 7: Build and launch the app bundle**

```bash
./Scripts/build-app.sh
open .build/Prata.app
sleep 1
pgrep -f "Prata.app/Contents/MacOS/Prata"
```

Expected: `pgrep` prints a PID (the app is running). It has no UI yet (no menu bar icon), so nothing visible happens — that's expected for this step.

```bash
pkill -f "Prata.app/Contents/MacOS/Prata"
```

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources Resources Scripts
git commit -m "$(cat <<'EOF'
Scaffold Prata as a two-target Swift package with app bundling

PrataCore holds testable logic, Prata is the thin AppKit executable.
Scripts/build-app.sh assembles Prata.app from the SPM build output.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Menu bar shell

**Files:**
- Create: `Sources/Prata/AppDelegate.swift`
- Modify: `Sources/Prata/main.swift`

**Interfaces:**
- Consumes: nothing from PrataCore yet.
- Produces: a running `AppDelegate` with a menu bar `NSStatusItem` and a Quit menu item. Later tasks (4, 6) extend `AppDelegate` to wire in `RecordingController` and `HotkeyController`.

- [ ] **Step 1: Write `AppDelegate.swift`**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "mic.fill",
            accessibilityDescription: "Prata"
        )

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Prata", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
```

- [ ] **Step 2: Wire it into `main.swift`**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
```

- [ ] **Step 3: Build and manually verify**

```bash
./Scripts/build-app.sh
open .build/Prata.app
```

Manual check (human): a microphone icon appears in the menu bar. Clicking it shows a "Quit Prata" item that quits the app. This can't be meaningfully asserted from the command line — confirm it visually.

```bash
pkill -f "Prata.app/Contents/MacOS/Prata" || true
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Prata
git commit -m "$(cat <<'EOF'
Add menu bar status item with Quit action

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Permissions manager

**Files:**
- Create: `Sources/PrataCore/PermissionsManager.swift`
- Test: `Tests/PrataCoreTests/PermissionsManagerTests.swift`

**Interfaces:**
- Produces: `PermissionsManager.requestMicrophoneAccess() async -> Bool`, `PermissionsManager.isAccessibilityTrusted() -> Bool`, `PermissionsManager.promptAccessibilityIfNeeded()`, `PermissionsManager.openAccessibilitySettings()`. Task 8 (AppDelegate wiring) calls these on launch.

- [ ] **Step 1: Write the failing test**

`Tests/PrataCoreTests/PermissionsManagerTests.swift`:

```swift
import XCTest
@testable import PrataCore

final class PermissionsManagerTests: XCTestCase {
    func testIsAccessibilityTrustedReturnsWithoutCrashing() {
        // We can't control the actual TCC permission state in a test run,
        // but this confirms the AXIsProcessTrusted() call links and returns
        // a plain Bool rather than crashing or hanging.
        let result = PermissionsManager.isAccessibilityTrusted()
        XCTAssertTrue(result == true || result == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter PermissionsManagerTests
```

Expected: FAIL — `PermissionsManager` doesn't exist yet.

- [ ] **Step 3: Write `PermissionsManager.swift`**

```swift
import AVFoundation
import ApplicationServices
import AppKit

public enum PermissionsManager {
    public static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public static func promptAccessibilityIfNeeded() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options: NSDictionary = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter PermissionsManagerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PrataCore/PermissionsManager.swift Tests/PrataCoreTests/PermissionsManagerTests.swift
git commit -m "$(cat <<'EOF'
Add PermissionsManager for mic and accessibility checks

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Audio capture and resampling

**Files:**
- Create: `Sources/PrataCore/AudioRecorder.swift`
- Test: `Tests/PrataCoreTests/AudioRecorderTests.swift`

**Interfaces:**
- Consumes: `FluidAudio.AudioConverter` (`resampleBuffer(_ buffer: AVAudioPCMBuffer) throws -> [Float]`, per [FluidAudio's Audio Conversion guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Guides/AudioConversion.md)).
- Produces: `AudioRecorder` with `start() throws`, `stop() throws -> [Float]` (16kHz mono samples), and the internal testable helper `AudioRecorder.resample(_:nativeFormat:) throws -> [Float]`. Task 6 (`RecordingController`) calls `start()`/`stop()`.

The engine capture itself (`start()`/`stop()`, which needs a real microphone) isn't unit-tested here — it's covered by the end-to-end manual verification in Task 9. What *is* unit-tested is the resampling math, via a synthetic buffer.

- [ ] **Step 1: Write the failing test**

`Tests/PrataCoreTests/AudioRecorderTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import PrataCore

final class AudioRecorderTests: XCTestCase {
    func testResampleConvertsToExpected16kHzSampleCount() throws {
        let nativeFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let oneSecondOfSamples = Int(nativeFormat.sampleRate)

        // One second of a 440Hz sine wave at the native rate.
        let sourceSamples: [Float] = (0..<oneSecondOfSamples).map { i in
            Float(sin(2.0 * Double.pi * 440.0 * Double(i) / nativeFormat.sampleRate))
        }

        let resampled = try AudioRecorder.resample(sourceSamples, nativeFormat: nativeFormat)

        // 48kHz -> 16kHz is a 3:1 ratio. Allow 5% tolerance for converter framing.
        let expectedCount = 16000.0
        XCTAssertEqual(Double(resampled.count), expectedCount, accuracy: expectedCount * 0.05)
    }

    func testResampleOfEmptyInputReturnsEmptyOutput() throws {
        let nativeFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let resampled = try AudioRecorder.resample([], nativeFormat: nativeFormat)
        XCTAssertTrue(resampled.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AudioRecorderTests
```

Expected: FAIL — `AudioRecorder` doesn't exist yet.

- [ ] **Step 3: Write `AudioRecorder.swift`**

```swift
import AVFoundation
import FluidAudio

public enum AudioRecorderError: Error {
    case bufferAllocationFailed
}

public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var nativeFormat: AVAudioFormat?
    private var samples: [Float] = []
    private let lock = NSLock()

    public init() {}

    public func start() throws {
        lock.lock()
        samples.removeAll()
        lock.unlock()

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        nativeFormat = format

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    public func stop() throws -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let captured = samples
        lock.unlock()

        guard !captured.isEmpty, let nativeFormat else { return [] }
        return try Self.resample(captured, nativeFormat: nativeFormat)
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channel0 = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        lock.lock()
        samples.append(contentsOf: channel0)
        lock.unlock()
    }

    /// Exposed internally (not `private`) so it's directly unit-testable
    /// with a synthetic buffer, without needing a real microphone.
    static func resample(_ nativeSamples: [Float], nativeFormat: AVAudioFormat) throws -> [Float] {
        guard !nativeSamples.isEmpty else { return [] }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: nativeFormat,
            frameCapacity: AVAudioFrameCount(nativeSamples.count)
        ) else {
            throw AudioRecorderError.bufferAllocationFailed
        }
        buffer.frameLength = buffer.frameCapacity

        nativeSamples.withUnsafeBufferPointer { pointer in
            buffer.floatChannelData![0].update(from: pointer.baseAddress!, count: nativeSamples.count)
        }

        return try AudioConverter().resampleBuffer(buffer)
    }
}
```

> **Note for the executor:** if `AudioConverter().resampleBuffer(buffer)` doesn't compile against the resolved `FluidAudio` package version, the API has drifted from what's documented. Check the actual signature with:
> ```bash
> grep -rn "func resampleBuffer" .build/checkouts/FluidAudio/Sources/
> ```
> and adjust the call to match. Same applies in Task 5 if `AsrManager`/`AsrModels` method names don't match.

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter AudioRecorderTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PrataCore/AudioRecorder.swift Tests/PrataCoreTests/AudioRecorderTests.swift
git commit -m "$(cat <<'EOF'
Add AudioRecorder: mic capture and 16kHz mono resampling

Capture logic is manually verified in Task 9 (needs a real mic); the
resampling math is unit-tested against a synthetic buffer.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Transcription engine (FluidAudio + Parakeet)

**Files:**
- Create: `Sources/PrataCore/TranscriptionEngine.swift`

**Interfaces:**
- Consumes: `FluidAudio.AsrModels.downloadAndLoad(version:) async throws -> AsrModels`, `FluidAudio.AsrManager(config:)`, `AsrManager.loadModels(_:) async throws`, `AsrManager.transcribe(_:source:) async throws -> ASRResult` (`.text: String`), per [FluidAudio's ASR Getting Started guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md) and [API reference](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md).
- Produces: `protocol TranscriptionEngine { func transcribe(_ samples: [Float]) async throws -> String }` and `final class ParakeetTranscriptionEngine: TranscriptionEngine`. Task 6 (`RecordingController`) depends on the protocol, not the concrete type.

This task has no automated test: the only thing to verify is that FluidAudio's model download and transcription actually work, which requires network access (first run) and a real audio sample — that's exactly what Task 9's end-to-end manual verification does. Writing a unit test that mocks `AsrManager` would test nothing real.

- [ ] **Step 1: Write `TranscriptionEngine.swift`**

```swift
import FluidAudio

public protocol TranscriptionEngine {
    func transcribe(_ samples: [Float]) async throws -> String
}

public enum TranscriptionEngineError: Error {
    case notLoaded
}

public final class ParakeetTranscriptionEngine: TranscriptionEngine {
    private var asrManager: AsrManager?

    public init() {}

    public func transcribe(_ samples: [Float]) async throws -> String {
        try await loadIfNeeded()
        guard let asrManager else { throw TranscriptionEngineError.notLoaded }
        let result = try await asrManager.transcribe(samples, source: .microphone)
        return result.text
    }

    private func loadIfNeeded() async throws {
        guard asrManager == nil else { return }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asrManager = manager
    }
}
```

> **Note for the executor:** same API-drift caveat as Task 4. If `AsrManager(config: .default)`, `.loadModels(_:)`, or `.transcribe(_:source:)` don't compile, check:
> ```bash
> grep -rn "func transcribe\|func loadModels\|class AsrManager\|struct AsrModels\|func downloadAndLoad" .build/checkouts/FluidAudio/Sources/FluidAudio/ASR/
> ```
> and adjust the two call sites (`loadIfNeeded`, `transcribe`) to match the actual resolved API. Don't guess — read the resolved source, since FluidAudio's own docs are inconsistent about method names between the top-level README and `Documentation/ASR/GettingStarted.md` (`loadModels` vs. `configure`).

- [ ] **Step 2: Build (no test — this compiles against a real dependency; correctness is checked in Task 9)**

```bash
swift build
```

Expected: builds without errors. If it doesn't, apply the note above.

- [ ] **Step 3: Commit**

```bash
git add Sources/PrataCore/TranscriptionEngine.swift
git commit -m "$(cat <<'EOF'
Add TranscriptionEngine protocol and FluidAudio/Parakeet implementation

Pluggable by design (spec section 3.2) so a Pianissimo-backed engine
can be added later behind the same protocol.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Paste service

**Files:**
- Create: `Sources/PrataCore/PasteService.swift`
- Test: `Tests/PrataCoreTests/PasteServiceTests.swift`

**Interfaces:**
- Produces: `PasteService.writeToPasteboard(_ text: String)` and `PasteService.paste()`. Task 7 (`RecordingController`) calls both after transcription.

`writeToPasteboard` is unit-tested (it's deterministic and needs no permissions). `paste()` simulates a global Cmd+V keystroke via CGEvent, which requires Accessibility permission for whatever process posts it — not something a unit test can assert; it's covered by Task 9's manual verification. Per spec §6, the AppleScript fallback for blocked synthetic keystrokes is deferred past this walking skeleton (noted in the spec as simplified for now) — `writeToPasteboard` alone already gives the user a manual `Cmd+V` fallback if `paste()` doesn't land.

- [ ] **Step 1: Write the failing test**

`Tests/PrataCoreTests/PasteServiceTests.swift`:

```swift
import XCTest
import AppKit
@testable import PrataCore

final class PasteServiceTests: XCTestCase {
    func testWriteToPasteboardPutsTextOnGeneralPasteboard() {
        let expected = "Prata testtranskript \(UUID().uuidString)"

        PasteService.writeToPasteboard(expected)

        let actual = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(actual, expected)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter PasteServiceTests
```

Expected: FAIL — `PasteService` doesn't exist yet.

- [ ] **Step 3: Write `PasteService.swift`**

```swift
import AppKit

public enum PasteService {
    public static func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Simulates Cmd+V. Requires Accessibility permission to be granted
    /// to this app (see PermissionsManager) — if it's not granted, this
    /// silently does nothing and the text is still on the pasteboard
    /// from writeToPasteboard, so the user can paste manually.
    public static func paste() {
        let virtualKeyV: CGKeyCode = 0x09
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter PasteServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PrataCore/PasteService.swift Tests/PrataCoreTests/PasteServiceTests.swift
git commit -m "$(cat <<'EOF'
Add PasteService: pasteboard write + simulated Cmd+V

AppleScript fallback for blocked synthetic keystrokes (spec section 6)
is deferred past the walking skeleton; the pasteboard write alone
already gives a manual Cmd+V fallback.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Hotkey controller and recording orchestrator

**Files:**
- Create: `Sources/PrataCore/HotkeyController.swift`
- Create: `Sources/PrataCore/RecordingController.swift`

**Interfaces:**
- Consumes: `AudioRecorder` (Task 4), `TranscriptionEngine` (Task 5), `PasteService` (Task 6), `KeyboardShortcuts.onKeyDown(for:)` / `.onKeyUp(for:)`.
- Produces: `HotkeyController(onStart:onStop:)` and `RecordingController`, with `startRecording()`, `stopRecordingAndTranscribe()`, `isRecording: Bool`, and `onStateChange: ((Bool) -> Void)?`. Task 8 (`AppDelegate`) instantiates both and connects them to the menu bar icon.

No automated test here: this is pure orchestration wiring real system APIs (global hotkey registration, the audio engine, an async network-backed transcription call) — there's no meaningful behavior to assert without actually pressing a key and speaking, which is Task 9.

- [ ] **Step 1: Write `HotkeyController.swift`**

```swift
import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", initial: .init(.f5))
}

public final class HotkeyController {
    public init(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) {
            onStart()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) {
            onStop()
        }
    }
}
```

The default hotkey is F5. This is a v1 simplification — the reference screenshots showed a bare held modifier key (e.g. Right ⌘), which needs a different mechanism (a `CGEventTap` on `flagsChanged`, not `KeyboardShortcuts`'s key+modifier model) and is deferred; F5 proves the hold-to-record flow with a standard, easily-testable hotkey.

- [ ] **Step 2: Write `RecordingController.swift`**

```swift
import Foundation

@MainActor
public final class RecordingController {
    private let recorder = AudioRecorder()
    private let engine: TranscriptionEngine

    public private(set) var isRecording = false
    public var onStateChange: ((Bool) -> Void)?

    public init(engine: TranscriptionEngine = ParakeetTranscriptionEngine()) {
        self.engine = engine
    }

    public func startRecording() {
        guard !isRecording else { return }
        do {
            try recorder.start()
            isRecording = true
            onStateChange?(true)
        } catch {
            print("Prata: failed to start recording: \(error)")
        }
    }

    public func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        isRecording = false
        onStateChange?(false)

        Task {
            do {
                let samples = try recorder.stop()
                guard !samples.isEmpty else {
                    print("Prata: no audio captured")
                    return
                }

                let text = try await engine.transcribe(samples)
                guard !text.isEmpty else {
                    print("Prata: empty transcription")
                    return
                }

                PasteService.writeToPasteboard(text)
                PasteService.paste()
                print("Prata: pasted \"\(text)\"")
            } catch {
                print("Prata: transcription failed: \(error)")
            }
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build
```

Expected: builds without errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/PrataCore/HotkeyController.swift Sources/PrataCore/RecordingController.swift
git commit -m "$(cat <<'EOF'
Add HotkeyController and RecordingController orchestration

Hold F5 to record; release to transcribe and paste. F5 is a v1
stand-in for a bare held modifier key, which needs a CGEventTap on
flagsChanged rather than KeyboardShortcuts's key+modifier model.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Wire everything into the AppDelegate

**Files:**
- Modify: `Sources/Prata/AppDelegate.swift`

**Interfaces:**
- Consumes: `RecordingController`, `HotkeyController`, `PermissionsManager` (all from `PrataCore`).
- Produces: a fully wired app — menu bar icon changes appearance while recording, permissions are requested on launch.

- [ ] **Step 1: Update `AppDelegate.swift`**

```swift
import AppKit
import PrataCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recordingController = RecordingController()
    private var hotkeyController: HotkeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(isRecording: false)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Prata", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        recordingController.onStateChange = { [weak self] isRecording in
            self?.updateIcon(isRecording: isRecording)
        }

        hotkeyController = HotkeyController(
            onStart: { [weak self] in self?.recordingController.startRecording() },
            onStop: { [weak self] in self?.recordingController.stopRecordingAndTranscribe() }
        )

        Task {
            _ = await PermissionsManager.requestMicrophoneAccess()
            if !PermissionsManager.isAccessibilityTrusted() {
                PermissionsManager.promptAccessibilityIfNeeded()
            }
        }
    }

    private func updateIcon(isRecording: Bool) {
        let symbolName = isRecording ? "mic.fill" : "mic"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isRecording ? "Prata (recording)" : "Prata"
        )
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: builds without errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Prata/AppDelegate.swift
git commit -m "$(cat <<'EOF'
Wire RecordingController and HotkeyController into the menu bar app

Icon switches between mic/mic.fill while recording. Mic and
Accessibility permissions are requested on launch.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: End-to-end manual verification

This task has no code changes — it's where the human confirms the walking skeleton actually works, since it requires a real microphone, real speech, and real System Settings permission prompts, none of which can be driven by an automated step.

**Files:** none.

- [ ] **Step 1: Build the app fresh**

```bash
./Scripts/build-app.sh
```

- [ ] **Step 2: Launch it and grant permissions**

```bash
open .build/Prata.app
```

On first launch: grant Microphone access when prompted. If Accessibility isn't already trusted, System Settings opens to the Accessibility pane — enable Prata there, then quit and relaunch the app (Accessibility grants often require a relaunch to take effect).

- [ ] **Step 3: Hold F5, speak, release**

With a text field focused somewhere (e.g. TextEdit or Notes), hold **F5**, say a short sentence in Swedish, and release. First run will also download the Parakeet model (a few hundred MB) — this happens once and will make the first transcription noticeably slower than subsequent ones.

Expected: the menu bar icon fills in (`mic.fill`) while F5 is held, and shortly after release the spoken text appears pasted at the cursor.

- [ ] **Step 4: Check timing**

Run the app from a terminal instead of via `open`, so `print()` output is visible:

```bash
.build/Prata.app/Contents/MacOS/Prata
```

Hold F5, speak, release, and note how long it takes between release and the `Prata: pasted "..."` log line appearing. This is the number to report back — it's the real answer to "how fast is it," on this hardware, with the stock multilingual model (not yet the Pianissimo conversion from spec §3.3, which should be noticeably more accurate on Swedish once built).

- [ ] **Step 5: Report results**

Note in the conversation: whether it worked, the transcription quality (especially on Swedish), and the release-to-paste latency. This determines whether to proceed to the rest of the v1 design (HUD, dictionary, model manager) or fix something first.
