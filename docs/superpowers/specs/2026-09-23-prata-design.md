# Prata — Design Spec

Date: 2026-09-23
Status: Draft, pending user review

## 1. Vision

A minimal, native, menu-bar-only push-to-talk dictation app for macOS
(Apple Silicon). Hold a global hotkey, speak, release — the transcript is
pasted at the cursor and copied to the clipboard as a safety net. Runs
100% on-device, is easy to hold entirely in your head, and is not tied to
one model family: transcription runs behind a small pluggable interface so
better or different models can be swapped in without touching the rest of
the app.

Non-goals for v1: streaming-only architecture, AI rewriting/"modes",
app-detection, meeting notes/diarization, cloud models, cross-platform
support.

## 2. User flow

1. User holds the configured hotkey (default: a function key, user
   remappable).
2. A small floating HUD appears near the cursor: mic icon, red stop
   indicator, live waveform driven by mic input level.
3. While held, the mic streams into an in-memory buffer. If the active
   transcription engine supports incremental/streaming inference, the HUD
   also shows live partial captions under the waveform (expandable via
   "Show more" for long utterances) — this is best-effort UI feedback
   only.
4. User releases the hotkey. The HUD closes immediately. The *entire*
   captured buffer is sent to the active engine for one batch
   transcription pass — this is always the source of truth for the
   final text, regardless of what the live captions showed, per the
   original design goal of batch-mode accuracy over streaming.
5. The result is run through the user's personal dictionary
   (find/replace), written to the system pasteboard, then auto-pasted at
   the current cursor position.
6. If auto-paste fails (blocked synthetic keystroke, no focused text
   field, etc.), the text remains on the pasteboard — user can `Cmd+V`
   manually. This fallback is always available, not just on failure.

## 3. Transcription engine architecture

### 3.1 Why not Whisper-only

The user's priority model, [KlangAI/pianissimo-sv](https://huggingface.co/KlangAI/pianissimo-sv),
is a 600M-parameter NeMo FastConformer-TDT model (a fine-tune of NVIDIA
Parakeet TDT v3), not a Whisper-family model. It cannot be run via
whisper.cpp/GGUF — that format/runtime doesn't implement this
architecture. It substantially outperforms KB-Whisper on Swedish WER
while running far faster.

**Security note:** a repo `blixten/pianissimo-sv-gguf` was found on
Hugging Face during research — no model card, zero engagement, uploaded
minutes before it was found, and technically implausible (this
architecture has no legitimate GGUF path). It is not used anywhere in
this design. The only trusted source for Pianissimo is the official
`KlangAI/pianissimo-sv` NeMo checkpoint.

### 3.2 Engine abstraction

```swift
protocol TranscriptionEngine {
    var id: String { get }
    var supportsStreamingPreview: Bool { get }
    func transcribe(_ samples: [Float]) async throws -> String
    func streamingPreview(_ samples: AsyncStream<[Float]>) -> AsyncStream<String>  // optional, only if supportsStreamingPreview
}
```

Concrete engines conform to this and are registered in a small model
registry. The app never hardcodes "Whisper" or "Parakeet" outside the
engine implementations — adding a new model family later means adding a
new engine, not touching app/UI code.

### 3.3 v1 engine: FluidAudio + Parakeet

[FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0
Swift SDK) runs Parakeet-family models natively on the Apple Neural
Engine via CoreML — no Python/PyTorch runtime shipped in the app.

- **Day one:** ship with FluidAudio's stock
  `FluidInference/parakeet-tdt-0.6b-v3-coreml` (multilingual, auto-
  downloads via FluidAudio's own model hub). This proves the entire
  pipeline (hotkey → capture → transcribe → paste) end-to-end without
  requiring any model conversion work first.
- **Phase 2 (separate follow-up task, not blocking v1):** convert
  `KlangAI/pianissimo-sv`'s NeMo checkpoint to CoreML using FluidAudio's
  own conversion process (`mobius` scripts — see their
  `Documentation/ModelConversion.md`). Because Pianissimo keeps Parakeet
  v3's exact architecture and tokenizer (only fine-tuned weights differ),
  the existing `parakeet-tdt-v3` conversion script is the starting point
  — swap in Pianissimo's state dict rather than writing a new pipeline
  from scratch. Once converted, host the `.mlmodelc` bundle (a
  Hugging Face repo under the user's own account, matching FluidAudio's
  expected layout) and register it as a second, higher-accuracy Swedish
  option in the model manager. This becomes the default once validated.
- Live partial captions (§2 step 3) use FluidAudio's
  `SlidingWindowAsrManager` when the loaded model/engine supports it.
  The stock v3 model supports this; whether the converted Pianissimo
  bundle does depends on the conversion — if not, that engine simply
  reports `supportsStreamingPreview == false` and the HUD shows waveform
  only, no partial text.

### 3.4 Future engines (not built now, just not architecturally blocked)

- whisper.cpp + KB-Whisper (Swedish-specific Whisper fine-tune), as a
  second engine behind the same protocol, for users who want an
  alternative or other-language models.
- Any other whisper.cpp-compatible GGUF model the user points the app at.

## 4. Model management

A settings tab lists known models (bundled registry entries, not
arbitrary URLs for v1): name, engine, size, installed/not, download
progress, delete. Downloads go through each engine's own trusted
mechanism (FluidAudio's Hugging Face-based `ModelHub` for Parakeet
models). No custom download/update code needs to be written for the v1
model — FluidAudio provides it.

## 5. Post-processing: personal dictionary

An ordered list of (find, replace) string pairs, case-insensitive
matching, applied to the final batch transcript before paste. Stored as
JSON in `Application Support`. Editable as a simple add/remove list in
Settings — no regex, no LLM rewriting, no per-app rules for v1.

## 6. Text insertion

Two-step, matching the researched failure modes of synthetic paste on
macOS:

1. Write the text to `NSPasteboard.general`.
2. Simulate `Cmd+V` via `CGEvent`.
3. If that doesn't succeed (e.g., blocked by the target app, custom
   keyboard layout issues), fall back to an AppleScript/System Events
   keystroke (`tell application "System Events" to keystroke "v" using
   command down`).
4. Either way, the text stays on the pasteboard afterward as a manual
   fallback.

## 7. Permissions

On first run, request:
- **Microphone** (standard `AVCaptureDevice` prompt).
- **Accessibility** (required for the global hotkey listener and
  synthetic paste) — app shows a short explainer and deep-links to
  System Settings → Privacy & Security → Accessibility.

## 8. App shell & UI

- Menu bar only app (`LSUIElement`/no Dock icon), built with
  AppKit + SwiftUI, Swift Package Manager project.
- Global hotkey via the `KeyboardShortcuts` library (hold-to-record
  semantics, not toggle), user-remappable.
- Floating HUD: borderless, always-on-top, click-through `NSPanel` —
  mic icon, red stop indicator, live waveform, optional live partial
  captions with "Show more" expansion, modeled on the reference
  screenshot provided.
- One settings window: hotkey picker, model manager list, dictionary
  editor, Mic/Accessibility permission status.
- No history, no multiple "modes," no onboarding beyond the permissions
  explainer.

## 9. Threading

- Audio capture (`AVAudioEngine`) runs on its own queue, buffering
  samples in memory.
- Transcription runs via FluidAudio's actor-based async API off the
  main actor.
- UI state updates are marshaled to the `MainActor`.
- No custom streaming/rolling-buffer code needs to be written for v1
  beyond what FluidAudio's `SlidingWindowAsrManager` already provides
  for the live-preview path.

## 10. Testing approach

- Unit tests for: dictionary find/replace logic, paste fallback
  decision logic (mockable), hotkey-hold state machine.
- Manual verification (no model in CI): record → transcribe → paste
  round-trip with the stock Parakeet v3 model, using the `run` skill to
  launch and drive the built app.
- No automated WER/accuracy testing for v1 — that lives in FluidAudio's
  own benchmark suite for the underlying models.

## 11. Open items for Phase 2 (explicitly deferred, not designed here)

- Pianissimo → CoreML conversion work itself (separate task).
- Where exactly the converted Pianissimo bundle is hosted (a Hugging
  Face repo under the user's account is assumed, to be confirmed when
  that phase starts).
- Whether/how to add whisper.cpp + KB-Whisper as a second engine.
