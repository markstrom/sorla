# Sorla Walking Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the smallest possible end-to-end slice of Sorla working: hold a hotkey, capture mic audio, transcribe it on-device with FluidAudio's Parakeet model, and paste the result at the cursor — so we can test whether it works and how fast it is, before building out the rest of the design.

**Architecture:** A menu-bar-only macOS app (no Dock icon) split into two Swift Package targets: `SorlaCore` (a library holding all testable logic — audio capture/resampling, the transcription engine wrapper, paste handling) and `Sorla` (a thin executable target with the AppKit entry point and menu bar UI, which is not unit-tested — it's verified by running the built app). No dictionary post-processing, no HUD, no settings window in this slice — those come after this is proven to work.

**Tech Stack:** Swift 5.10, Swift Package Manager, AppKit, AVFoundation, [FluidAudio](https://github.com/FluidInference/FluidAudio) (on-device ASR via CoreML/ANE), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (global hotkey).

**Spec:** [docs/superpowers/specs/2026-09-23-sorla-design.md](../specs/2026-09-23-sorla-design.md) — this plan implements §12 ("First build / walking skeleton") specifically, using the engine choice from §3.3 (FluidAudio + stock `parakeet-tdt-0.6b-v3-coreml`) and the paste mechanism from §6 (simplified: CGEvent Cmd+V only, no AppleScript fallback yet — see Task 6 for why).

## Global Constraints

- Platform floor: macOS 14 (Sonoma). Set via `platforms: [.macOS(.v14)]` in Package.swift and `LSMinimumSystemVersion` 14.0 in Info.plist.
- Swift tools version: 5.10.
- Dependencies pinned with `from:` floors: `FluidAudio` from `0.16.1`, `KeyboardShortcuts` from `3.1.0`.
- App is unsandboxed (not for Mac App Store distribution) — this avoids sandbox entitlement complexity for mic capture, global hotkeys, and synthetic paste events, none of which are compatible with the App Sandbox in the way this app needs them.
- Bundle identifier: `com.sorla.app`. App name: `Sorla` (per user instruction — matches the project directory name).
- No personal dictionary, no HUD, no settings window in this plan — see spec §12.
- All code is written from scratch. No code copied from other projects, and no attribution, "based on", "inspired by", or "Powered by" references to other projects anywhere in source files or the repo (user requirement). Dependencies are consumed only through SwiftPM.
- Comments: none by default; at most one short line where the *why* is non-obvious. No multi-line doc comments. No comments referring to tasks or the plan.
- The build must produce no warnings from `Sources/` or `Tests/` (dependency warnings are out of scope).
- Git commits use the repo's configured identity (`1905972+markstrom@users.noreply.github.com`, already set locally) and end with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer.

---

## File Structure

```
Package.swift
Resources/
  Info.plist
Scripts/
  build-app.sh
.gitignore
Sources/
  SorlaCore/
    SorlaCore.swift            # empty placeholder, Task 1 creates / Task 3 deletes
    AudioRecorder.swift        # mic capture + resampling to 16kHz mono
    TranscriptionEngine.swift  # protocol + ParakeetTranscriptionEngine
    PasteService.swift         # pasteboard write + CGEvent Cmd+V
    PermissionsManager.swift   # mic + accessibility permission checks
    HotkeyController.swift     # KeyboardShortcuts wiring, hold-to-record
    RecordingController.swift  # orchestrates the above, MainActor
  Sorla/
    main.swift                 # NSApplication bootstrap (no @main App lifecycle)
    AppDelegate.swift           # NSStatusItem menu bar UI, wires RecordingController
Tests/
  SorlaCoreTests/
    AudioRecorderTests.swift
    ParakeetTranscriptionEngineTests.swift   # opt-in, SORLA_ASR_INTEGRATION=1
    PasteServiceTests.swift
```

`SorlaCore` holds everything with real logic to test. `Sorla` is deliberately thin — AppKit UI wiring that's verified by running the app, not by unit tests.

---

### Task 1: Project scaffold and app bundle packaging

**Files:**
- Create: `.gitignore`
- Create: `Package.swift` (and the generated `Package.resolved`)
- Create: `Sources/SorlaCore/SorlaCore.swift` (empty placeholder so the target isn't empty)
- Create: `Sources/Sorla/main.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`

**Interfaces:**
- Produces: a `SorlaCore` library target and a `Sorla` executable target that later tasks add files to. A `Sorla.app` bundle buildable via `Scripts/build-app.sh`.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Sorla",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.16.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "SorlaCore",
            dependencies: [
                "FluidAudio",
                "KeyboardShortcuts",
            ],
            path: "Sources/SorlaCore"
        ),
        .executableTarget(
            name: "Sorla",
            dependencies: ["SorlaCore"],
            path: "Sources/Sorla"
        ),
    ]
)
```

(No test target yet — SwiftPM rejects a test target whose directory doesn't exist. Task 4 adds it together with the first test file.)

- [ ] **Step 2: Create an empty placeholder so `SorlaCore` isn't an empty target**

Create `Sources/SorlaCore/SorlaCore.swift` as an **empty file** (zero bytes, no comments). Task 3 deletes it when the first real `SorlaCore` file lands.

- [ ] **Step 3: Create the executable entry point**

`Sources/Sorla/main.swift`:

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
    <string>Sorla</string>
    <key>CFBundleDisplayName</key>
    <string>Sorla</string>
    <key>CFBundleIdentifier</key>
    <string>com.sorla.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>Sorla</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Sorla behöver mikrofonåtkomst för att transkribera din röst till text.</string>
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

APP_NAME="Sorla.app"
APP_DIR=".build/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/Sorla "$APP_DIR/Contents/MacOS/Sorla"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

shopt -s nullglob
for bundle in .build/release/*.bundle; do
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
shopt -u nullglob

IDENTITY="${SORLA_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign --force --deep --sign "$IDENTITY" "$APP_DIR"

echo "Built $APP_DIR (signed with: $IDENTITY)"
```

Why the extra lines: dependency resource bundles (SwiftPM puts them at `.build/release/*.bundle`) must sit in `Contents/Resources` or `Bundle.module` traps at runtime. Signing with a stable Apple Development identity (selected by hash, because this machine has two identities with the same name) keeps the macOS Accessibility grant valid across rebuilds; an ad-hoc signature (`-`) changes every build and forces re-granting. `SORLA_SIGN_IDENTITY` overrides; ad-hoc is the fallback when no identity exists.

- [ ] **Step 6: Make the script executable and build**

```bash
chmod +x Scripts/build-app.sh
swift build
```

Expected: builds with no errors. First build resolves and compiles FluidAudio and KeyboardShortcuts, which takes a few minutes.

Also create `.gitignore` at the repo root:

```
.build/
.swiftpm/
*.xcodeproj/
DerivedData/
```

(`.superpowers/` already carries its own nested `.gitignore`; leave it alone.)

- [ ] **Step 7: Build and launch the app bundle**

```bash
./Scripts/build-app.sh
open .build/Sorla.app
sleep 1
pgrep -f "Sorla.app/Contents/MacOS/Sorla"
```

Expected: `pgrep` prints a PID (the app is running). It has no UI yet (no menu bar icon), so nothing visible happens — that's expected for this step.

```bash
pkill -f "Sorla.app/Contents/MacOS/Sorla"
```

- [ ] **Step 8: Commit**

```bash
git add .gitignore Package.swift Package.resolved Sources Resources Scripts
git commit -m "$(cat <<'EOF'
Scaffold Sorla as a two-target Swift package with app bundling

SorlaCore holds testable logic, Sorla is the thin AppKit executable.
Scripts/build-app.sh assembles Sorla.app from the SPM build output.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Menu bar shell

**Files:**
- Create: `Sources/Sorla/AppDelegate.swift`
- Modify: `Sources/Sorla/main.swift`

**Interfaces:**
- Consumes: nothing from SorlaCore yet.
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
            accessibilityDescription: "Sorla"
        )

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Sorla", action: #selector(quit), keyEquivalent: "q"))
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
open .build/Sorla.app
```

Automated check: `sleep 1; pgrep -f "Sorla.app/Contents/MacOS/Sorla"` prints a PID (the app launched with the delegate and didn't crash). The visual check — mic icon in the menu bar, "Quit Sorla" quits — is done by the human in Task 9.

```bash
pkill -f "Sorla.app/Contents/MacOS/Sorla" || true
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Sorla
git commit -m "$(cat <<'EOF'
Add menu bar status item with Quit action

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Permissions manager

**Files:**
- Create: `Sources/SorlaCore/PermissionsManager.swift`
- Delete: `Sources/SorlaCore/SorlaCore.swift` (the empty Task 1 placeholder — no longer needed once a real file exists)

**Interfaces:**
- Produces: `PermissionsManager.requestMicrophoneAccess() async -> Bool`, `PermissionsManager.isAccessibilityTrusted() -> Bool`, `PermissionsManager.promptAccessibilityIfNeeded()`. Task 8 (AppDelegate wiring) calls these on launch.

No unit test: these are one-line pass-throughs to OS permission APIs whose result depends on the machine's TCC state, so a test could only assert that a Bool is a Bool. They're verified by the real permission prompts in Task 9.

- [ ] **Step 1: Write `PermissionsManager.swift`**

```swift
import AVFoundation
import ApplicationServices

public enum PermissionsManager {
    public static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public static func promptAccessibilityIfNeeded() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options: NSDictionary = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
```

- [ ] **Step 2: Delete the placeholder and build**

```bash
git rm Sources/SorlaCore/SorlaCore.swift
swift build
```

Expected: builds with no errors and no warnings from `Sources/`.

- [ ] **Step 3: Commit**

```bash
git add Sources/SorlaCore/PermissionsManager.swift
git commit -m "$(cat <<'EOF'
Add PermissionsManager for mic and accessibility checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Audio capture and resampling

**Files:**
- Create: `Sources/SorlaCore/AudioRecorder.swift`
- Modify: `Package.swift` (add the test target)
- Test: `Tests/SorlaCoreTests/AudioRecorderTests.swift`

**Interfaces:**
- Consumes: `FluidAudio.AudioConverter` (`resampleBuffer(_ buffer: AVAudioPCMBuffer) throws -> [Float]`, per [FluidAudio's Audio Conversion guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Guides/AudioConversion.md)).
- Produces: `AudioRecorder` with `start() throws`, `stop() throws -> [Float]` (16kHz mono samples), and the internal testable helper `AudioRecorder.resample(_:sampleRate:) throws -> [Float]`. Task 7 (`RecordingController`) calls `start()`/`stop()`.

The engine capture itself (`start()`/`stop()`, which needs a real microphone) isn't unit-tested here — it's covered by the end-to-end manual verification in Task 9. What *is* unit-tested is the resampling math, via a synthetic buffer.

Only channel 0 of the input is kept, so `resample` always wraps samples in a **mono** buffer at the captured sample rate. (Wrapping channel-0 data in the input's native multi-channel format would leave the other channels uninitialized, and the converter's stereo→mono mix would average garbage into the result.)

- [ ] **Step 0: Add the test target to `Package.swift`**

Append to the `targets` array, after the `Sorla` executable target:

```swift
        .testTarget(
            name: "SorlaCoreTests",
            dependencies: ["SorlaCore"],
            path: "Tests/SorlaCoreTests"
        ),
```

- [ ] **Step 1: Write the failing test**

`Tests/SorlaCoreTests/AudioRecorderTests.swift`:

```swift
import XCTest
import AVFoundation
@testable import SorlaCore

final class AudioRecorderTests: XCTestCase {
    func testResampleConvertsOneSecondAt48kHzTo16kSamples() throws {
        let sampleRate = 48000.0
        let sourceSamples: [Float] = (0..<Int(sampleRate)).map { i in
            Float(sin(2.0 * Double.pi * 440.0 * Double(i) / sampleRate))
        }

        let resampled = try AudioRecorder.resample(sourceSamples, sampleRate: sampleRate)

        let expectedCount = 16000.0
        XCTAssertEqual(Double(resampled.count), expectedCount, accuracy: expectedCount * 0.05)
    }

    func testResamplePreservesSignalEnergy() throws {
        let sampleRate = 44100.0
        let sourceSamples: [Float] = (0..<Int(sampleRate)).map { i in
            Float(0.5 * sin(2.0 * Double.pi * 440.0 * Double(i) / sampleRate))
        }

        let resampled = try AudioRecorder.resample(sourceSamples, sampleRate: sampleRate)

        let rms = sqrt(resampled.map { $0 * $0 }.reduce(0, +) / Float(resampled.count))
        XCTAssertEqual(rms, 0.5 / sqrt(2), accuracy: 0.05)
    }

    func testResampleOfEmptyInputReturnsEmptyOutput() throws {
        let resampled = try AudioRecorder.resample([], sampleRate: 48000)
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
    private var sampleRate: Double = 0
    private var samples: [Float] = []
    private let lock = NSLock()

    public init() {}

    public func start() throws {
        lock.lock()
        samples.removeAll()
        lock.unlock()

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        sampleRate = format.sampleRate

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

        guard !captured.isEmpty else { return [] }
        return try Self.resample(captured, sampleRate: sampleRate)
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let channel0 = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        lock.lock()
        samples.append(contentsOf: channel0)
        lock.unlock()
    }

    static func resample(_ nativeSamples: [Float], sampleRate: Double) throws -> [Float] {
        guard !nativeSamples.isEmpty else { return [] }

        guard
            let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: monoFormat,
                frameCapacity: AVAudioFrameCount(nativeSamples.count)
            )
        else {
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
git add Package.swift Sources/SorlaCore/AudioRecorder.swift Tests/SorlaCoreTests/AudioRecorderTests.swift
git commit -m "$(cat <<'EOF'
Add AudioRecorder: mic capture and 16kHz mono resampling

Live capture needs a real mic and is verified by hand; the resampling
path is unit-tested against synthetic sine buffers.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Transcription engine (FluidAudio + Parakeet)

**Files:**
- Create: `Sources/SorlaCore/TranscriptionEngine.swift`
- Test: `Tests/SorlaCoreTests/ParakeetTranscriptionEngineTests.swift`

**Interfaces:**
- Consumes: `FluidAudio.AsrModels.downloadAndLoad(version:) async throws -> AsrModels`, `FluidAudio.AsrManager(config:)`, `AsrManager.loadModels(_:) async throws`, `AsrManager.transcribe(_:source:) async throws -> ASRResult` (`.text: String`), per [FluidAudio's ASR Getting Started guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/GettingStarted.md) and [API reference](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/API.md).
- Produces: `protocol TranscriptionEngine { func transcribe(_ samples: [Float]) async throws -> String }` and `final class ParakeetTranscriptionEngine: TranscriptionEngine`. Task 7 (`RecordingController`) depends on the protocol, not the concrete type.

A mock-based unit test would test nothing real. Instead this task adds an **opt-in integration test** that runs the real engine on real speech: macOS's built-in `say` command synthesizes an English sentence to an audio file, FluidAudio converts it to 16kHz mono, and the engine must transcribe it. It downloads the Parakeet v3 model (hundreds of MB) on first run, so it only runs when `SORLA_ASR_INTEGRATION=1` is set and is skipped otherwise — the default `swift test` stays fast and offline.

- [ ] **Step 1: Write `TranscriptionEngine.swift`**

```swift
import FluidAudio

public protocol TranscriptionEngine: Sendable {
    func prepare() async throws
    func transcribe(_ samples: [Float]) async throws -> String
}

public actor ParakeetTranscriptionEngine: TranscriptionEngine {
    private var asrManager: AsrManager?

    public init() {}

    public func prepare() async throws {
        _ = try await loadedManager()
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        let manager = try await loadedManager()
        let result = try await manager.transcribe(samples, source: .microphone)
        return result.text
    }

    private func loadedManager() async throws -> AsrManager {
        if let asrManager { return asrManager }
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        asrManager = manager
        return manager
    }
}
```

`prepare()` exists so the app can download/compile the model at launch instead of on the first hotkey release — otherwise the first dictation would include a multi-hundred-MB download and CoreML compile, which would make the latency measurement in Task 9 meaningless. It's an `actor` so two overlapping calls can't both start a load.

> **Note for the executor:** same API-drift caveat as Task 4. If `AsrManager(config: .default)`, `.loadModels(_:)`, or `.transcribe(_:source:)` don't compile, check:
> ```bash
> grep -rn "func transcribe\|func loadModels\|class AsrManager\|struct AsrModels\|func downloadAndLoad" .build/checkouts/FluidAudio/Sources/FluidAudio/ASR/
> ```
> and adjust the call sites in `loadedManager()` and `transcribe` to match the actual resolved API. Don't guess — read the resolved source, since FluidAudio's own docs are inconsistent about method names between the top-level README and `Documentation/ASR/GettingStarted.md` (`loadModels` vs. `configure`). If `AsrManager` is not `Sendable` and that produces warnings when stored in the actor, report it as a concern rather than silencing it with `@unchecked`/`@preconcurrency`.

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: builds with no errors and no warnings from `Sources/`. If it doesn't compile, apply the note above.

- [ ] **Step 3: Write the opt-in integration test**

`Tests/SorlaCoreTests/ParakeetTranscriptionEngineTests.swift`:

```swift
import XCTest
import FluidAudio
@testable import SorlaCore

final class ParakeetTranscriptionEngineTests: XCTestCase {
    func testTranscribesSynthesizedEnglishSpeech() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SORLA_ASR_INTEGRATION"] == "1",
            "Set SORLA_ASR_INTEGRATION=1 to run (downloads the Parakeet model)."
        )

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sorla-asr-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", audioURL.path, "The quick brown fox jumps over the lazy dog."]
        try say.run()
        say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0)

        let samples = try AudioConverter().resampleAudioFile(path: audioURL.path)
        let engine = ParakeetTranscriptionEngine()
        try await engine.prepare()

        let start = Date()
        let text = try await engine.transcribe(samples)
        let elapsed = Date().timeIntervalSince(start)
        print("Parakeet transcribed \(Double(samples.count) / 16000)s of audio in \(elapsed)s: \(text)")

        let lowered = text.lowercased()
        XCTAssertTrue(lowered.contains("fox"), "Unexpected transcript: \(text)")
        XCTAssertTrue(lowered.contains("lazy dog"), "Unexpected transcript: \(text)")
    }
}
```

- [ ] **Step 4: Run it both ways**

```bash
swift test --filter ParakeetTranscriptionEngineTests
```

Expected: the test is reported as **skipped** (no env var).

```bash
SORLA_ASR_INTEGRATION=1 swift test --filter ParakeetTranscriptionEngineTests
```

Expected: PASS, and the printed line shows the transcript and how long transcription took. The first run downloads the model; that's expected to take a while. Put the printed timing line in your report.

- [ ] **Step 5: Commit**

```bash
git add Sources/SorlaCore/TranscriptionEngine.swift Tests/SorlaCoreTests/ParakeetTranscriptionEngineTests.swift
git commit -m "$(cat <<'EOF'
Add TranscriptionEngine protocol and FluidAudio/Parakeet implementation

Pluggable by design (spec section 3.2) so a Pianissimo-backed engine
can be added later behind the same protocol.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Paste service

**Files:**
- Create: `Sources/SorlaCore/PasteService.swift`
- Test: `Tests/SorlaCoreTests/PasteServiceTests.swift`

**Interfaces:**
- Produces: `PasteService.writeToPasteboard(_ text: String)` and `PasteService.paste()`. Task 7 (`RecordingController`) calls both after transcription.

`writeToPasteboard` is unit-tested (it's deterministic and needs no permissions). `paste()` simulates a global Cmd+V keystroke via CGEvent, which requires Accessibility permission for whatever process posts it — not something a unit test can assert; it's covered by Task 9's manual verification. Per spec §6, the AppleScript fallback for blocked synthetic keystrokes is deferred past this walking skeleton (noted in the spec as simplified for now) — `writeToPasteboard` alone already gives the user a manual `Cmd+V` fallback if `paste()` doesn't land.

- [ ] **Step 1: Write the failing test**

`Tests/SorlaCoreTests/PasteServiceTests.swift`:

```swift
import XCTest
import AppKit
@testable import SorlaCore

final class PasteServiceTests: XCTestCase {
    private var savedClipboard: String?

    override func setUp() {
        savedClipboard = NSPasteboard.general.string(forType: .string)
    }

    override func tearDown() {
        NSPasteboard.general.clearContents()
        if let savedClipboard {
            NSPasteboard.general.setString(savedClipboard, forType: .string)
        }
    }

    func testWriteToPasteboardPutsTextOnGeneralPasteboard() {
        let expected = "Sorla testtranskript \(UUID().uuidString)"

        PasteService.writeToPasteboard(expected)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected)
    }

    func testWriteToPasteboardReplacesPreviousContent() {
        PasteService.writeToPasteboard("första")
        PasteService.writeToPasteboard("andra")

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "andra")
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

    // Without Accessibility permission the OS drops these events; the text stays on the pasteboard.
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
git add Sources/SorlaCore/PasteService.swift Tests/SorlaCoreTests/PasteServiceTests.swift
git commit -m "$(cat <<'EOF'
Add PasteService: pasteboard write + simulated Cmd+V

AppleScript fallback for blocked synthetic keystrokes (spec section 6)
is deferred past the walking skeleton; the pasteboard write alone
already gives a manual Cmd+V fallback.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Hotkey controller and recording orchestrator

**Files:**
- Create: `Sources/SorlaCore/HotkeyController.swift`
- Create: `Sources/SorlaCore/RecordingController.swift`

**Interfaces:**
- Consumes: `AudioRecorder` (Task 4), `TranscriptionEngine` (Task 5), `PasteService` (Task 6), `KeyboardShortcuts.onKeyDown(for:)` / `.onKeyUp(for:)`.
- Produces: `HotkeyController(onStart:onStop:)` and `RecordingController`, with `prepare()`, `startRecording()`, `stopRecordingAndTranscribe()`, `isRecording: Bool`, and `onStateChange: ((Bool) -> Void)?`. Task 8 (`AppDelegate`) instantiates both, calls `prepare()` at launch, and connects the state callback to the menu bar icon.

No automated test here: this is pure orchestration wiring real system APIs (global hotkey registration, the audio engine, the transcription engine) — there's no meaningful behavior to assert without actually pressing a key and speaking, which is Task 9.

- [ ] **Step 1: Write `HotkeyController.swift`**

```swift
import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", initial: .init(.space, modifiers: [.option]))
}

@MainActor
public final class HotkeyController {
    public init(onStart: @escaping @MainActor () -> Void, onStop: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) {
            onStart()
        }
        KeyboardShortcuts.onKeyUp(for: .pushToTalk) {
            onStop()
        }
    }
}
```

The default hotkey is **⌥Space** (hold Option+Space). Not F5: on current Apple keyboards F5 without `fn` is the system Dictation key, so it would trigger macOS's own dictation instead of Sorla. A bare held modifier (the Right ⌘ from the reference screenshot) needs a `CGEventTap` on `flagsChanged` rather than `KeyboardShortcuts`'s key+modifier model, and is deferred.

If `KeyboardShortcuts`'s handler closures are not main-actor-isolated and calling the `@MainActor` closures from them produces an isolation warning or error, fix it inside `HotkeyController` (e.g. `MainActor.assumeIsolated { onStart() }` — the library delivers these on the main thread) rather than dropping the `@MainActor` annotations. The build must be free of warnings from `Sources/`.

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

    public func prepare() {
        Task {
            let start = Date()
            do {
                try await engine.prepare()
                print("Sorla: model ready in \(Self.format(Date().timeIntervalSince(start)))")
            } catch {
                print("Sorla: model preparation failed: \(error)")
            }
        }
    }

    public func startRecording() {
        guard !isRecording else { return }
        do {
            try recorder.start()
            isRecording = true
            onStateChange?(true)
        } catch {
            print("Sorla: failed to start recording: \(error)")
        }
    }

    public func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        isRecording = false
        onStateChange?(false)

        let released = Date()
        let samples: [Float]
        do {
            samples = try recorder.stop()
        } catch {
            print("Sorla: failed to stop recording: \(error)")
            return
        }
        guard !samples.isEmpty else {
            print("Sorla: no audio captured")
            return
        }

        Task {
            do {
                let text = try await engine.transcribe(samples)
                guard !text.isEmpty else {
                    print("Sorla: empty transcription")
                    return
                }
                PasteService.writeToPasteboard(text)
                PasteService.paste()
                let audioSeconds = Double(samples.count) / 16_000
                print("Sorla: \(Self.format(audioSeconds)) audio -> pasted in \(Self.format(Date().timeIntervalSince(released))): \"\(text)\"")
            } catch {
                print("Sorla: transcription failed: \(error)")
            }
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }
}
```

The recorder is stopped synchronously on key release (so the mic turns off immediately); only transcription and paste run in the `Task`. The timing line is the release-to-paste latency Task 9 reports.

- [ ] **Step 3: Build**

```bash
swift build
```

Expected: builds with no errors and no warnings from `Sources/`.

- [ ] **Step 4: Commit**

```bash
git add Sources/SorlaCore/HotkeyController.swift Sources/SorlaCore/RecordingController.swift
git commit -m "$(cat <<'EOF'
Add HotkeyController and RecordingController orchestration

Hold Option+Space to record; release to transcribe and paste. F5 was
avoided because it is the system Dictation key on Apple keyboards; a
bare held modifier needs a CGEventTap and comes later.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Wire everything into the AppDelegate

**Files:**
- Modify: `Sources/Sorla/AppDelegate.swift`

**Interfaces:**
- Consumes: `RecordingController`, `HotkeyController`, `PermissionsManager` (all from `SorlaCore`).
- Produces: a fully wired app — menu bar icon changes appearance while recording, the model is prepared at launch, permissions are requested on launch.

- [ ] **Step 1: Update `AppDelegate.swift`**

```swift
import AppKit
import SorlaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recordingController = RecordingController()
    private var hotkeyController: HotkeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(isRecording: false)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Sorla", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        recordingController.onStateChange = { [weak self] isRecording in
            self?.updateIcon(isRecording: isRecording)
        }

        hotkeyController = HotkeyController(
            onStart: { [weak self] in self?.recordingController.startRecording() },
            onStop: { [weak self] in self?.recordingController.stopRecordingAndTranscribe() }
        )

        recordingController.prepare()

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
            accessibilityDescription: isRecording ? "Sorla (recording)" : "Sorla"
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
git add Sources/Sorla/AppDelegate.swift
git commit -m "$(cat <<'EOF'
Wire RecordingController and HotkeyController into the menu bar app

Icon switches between mic/mic.fill while recording. Mic and
Accessibility permissions are requested on launch.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
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
open .build/Sorla.app
```

On first launch: grant Microphone access when prompted. If Accessibility isn't already trusted, System Settings opens to the Accessibility pane — enable Sorla there, then quit and relaunch the app (Accessibility grants often require a relaunch to take effect).

- [ ] **Step 3: Hold ⌥Space, speak, release**

Check the menu bar: a mic icon is shown, and clicking it offers "Quit Sorla". With a text field focused somewhere (e.g. TextEdit or Notes), hold **⌥Space** (Option+Space), say a short sentence in Swedish, and release. The model is prepared at launch; if you dictate before it's ready (first launch downloads a few hundred MB), that dictation waits for it.

Expected: the menu bar icon fills in (`mic.fill`) while ⌥Space is held, and shortly after release the spoken text appears pasted at the cursor.

- [ ] **Step 4: Check timing**

Run the app from a terminal instead of via `open`, so `print()` output is visible:

```bash
.build/Sorla.app/Contents/MacOS/Sorla
```

Wait for `Sorla: model ready in …`, then hold ⌥Space, speak, release. Each dictation prints `Sorla: <audio length> audio -> pasted in <latency>: "<text>"`. This is the number to report back — it's the real answer to "how fast is it," on this hardware, with the stock multilingual model (not yet the Pianissimo conversion from spec §3.3, which should be noticeably more accurate on Swedish once built).

- [ ] **Step 5: Report results**

Note in the conversation: whether it worked, the transcription quality (especially on Swedish), and the release-to-paste latency. This determines whether to proceed to the rest of the v1 design (HUD, dictionary, model manager) or fix something first.
