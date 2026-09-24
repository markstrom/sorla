# Sorla

**Talk. Release. Done.**

Sorla is push-to-talk dictation for the Mac. Hold a key (Right ⌘ by default), speak Swedish, and let go. The text is pasted where your cursor is, in whatever app you're using.

Sorla lives in the menu bar and stays out of the way until you use it. Speech recognition runs entirely on your Mac, on the Apple Neural Engine. No account, no cloud, no analytics.

**[Download Sorla](https://github.com/markstrom/sorla/releases/latest)** · **[Website: sorla.zerolabs.se](https://sorla.zerolabs.se)** · [Help (Swedish)](https://sorla.zerolabs.se/support) · [Privacy](https://sorla.zerolabs.se/privacy)

## Built on Klang Pianissimo

Sorla understands Swedish thanks to **Klang Pianissimo**, a Swedish speech recognition model by **Klang AI AB**, released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

- Model: [KlangAI/pianissimo-sv](https://huggingface.co/KlangAI/pianissimo-sv)
- Pianissimo is fine-tuned from [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (CC BY 4.0).
- Sorla runs a Core ML conversion of Pianissimo with unchanged weights: [markstrom/pianissimo-sv-coreml](https://huggingface.co/markstrom/pianissimo-sv-coreml).

Thank you, Klang, for building Pianissimo and sharing it openly. Sorla would not exist without it.

> Sorla is an independent app. It is not made, endorsed or supported by Klang AI AB.

Sorla also builds on:

- [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0), which runs the model with Core ML.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT), for custom shortcuts.

## Features

- **Push to talk or toggle.** Hold the key while you speak, or press once to start and once more to stop.
- **Your key.** Right ⌘ by default. Pick Right ⌥, Right ⌃ or a custom shortcut instead.
- **A small indicator** at the top of the screen, with a live waveform while you speak.
- **Paste Last.** ⌃⌥V pastes the most recent text again, wherever you are now. The text is kept for five minutes, and forgotten at once when the screen locks or the Mac sleeps. Turn off **Keep last transcription** in Settings and Sorla itself keeps no text for Paste Last once it has been pasted. The clipboard is separate: the text stays on it when **Put back what you had copied** is off, or when Sorla couldn't paste and left the text on the clipboard instead.
- **Your clipboard is kept.** Whatever you had copied is still there after Sorla pastes.
- Soft start and stop sounds, and optional launch at login.
- English and Swedish user interface.
- Text appears when you let go, not while you speak: Klang Pianissimo transcribes a whole utterance at once and isn't built for streaming, and transcribing in chunks would mean worse text. From release to text takes about half a second.

## Requirements

- A Mac with Apple Silicon (M1 or later)
- macOS 14 Sonoma or later
- About 700 MB of free space for the speech model, which is downloaded on first launch

## Install

1. Download the DMG from [the website](https://sorla.zerolabs.se) or the [latest release](https://github.com/markstrom/sorla/releases/latest).
2. Open it and drag **Sorla** to **Applications**.
3. Open Sorla from the Applications folder.
4. Grant **Microphone** and **Accessibility** access. The welcome window walks you through both and downloads the model.
5. Hold Right ⌘ and speak.

Or with [Homebrew](https://brew.sh):

```sh
brew install --cask markstrom/tap/sorla
```

Update later with `brew upgrade --cask sorla`.

### Updates

Sorla can update itself. When **Check for Updates…** in the menu (or **Check Now** in Settings › Updates) finds a newer version, choose **Install and Relaunch** there or in the menu's status row. Sorla downloads that exact release from GitHub, checks that it is signed by Sorla's developer, notarized by Apple and the version that was found, swaps it in at the same path, and relaunches in a few seconds, waiting for any dictation in flight. The previous version stays next to it until the new one has started. If anything fails, the current version is kept.

With both **Check for updates automatically** and **Install updates automatically** turned on (both are off by default), Sorla downloads and verifies a new version in the background and installs it once you haven't dictated for 10 minutes, or at its next launch.

If Sorla can't replace itself (a folder you can't write to, or a copy macOS runs from a temporary location), it offers **Download** instead. A Homebrew install is updated with `brew upgrade --cask sorla`.

### If macOS blocks the app

Sorla is signed with Developer ID and notarized by Apple, so this is rare. Step-by-step help, including what to do if Accessibility won't turn on, is on the [help page](https://sorla.zerolabs.se/support#oppna) (in Swedish).

If macOS says Sorla can't be opened, either:

- open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**, or
- remove the quarantine flag in Terminal:

  ```sh
  xattr -dr com.apple.quarantine /Applications/Sorla.app
  ```

## Privacy

Your voice and your text never leave your Mac. Audio is processed in memory and never saved. The last text stays in memory for Paste Last for at most five minutes, or not at all with Keep last transcription turned off.

Sorla uses the network only to:

- download the speech model from Hugging Face on first launch,
- check for updates, asking GitHub for the latest app version and Hugging Face for a newer model in one check, only when you ask it to or, if you turn it on, automatically about once a day, and
- download a new version of Sorla from GitHub, only when you choose Install and Relaunch or have turned on both automatic checks and automatic installs. Before installing it, macOS asks Apple whether it is notarized.

There are no accounts, no analytics and no tracking. Once the model is installed, Sorla works offline. Read the full [privacy policy](https://sorla.zerolabs.se/privacy).

## Principles

Every feature in Sorla is weighed against [the Sorla Manifesto](MANIFESTO.md): one purpose, nothing leaves the Mac, never make the user wait, calm by default.

## Building from source

Sorla is a Swift package. You need Xcode (or the Swift toolchain) for macOS 14 or later.

```sh
swift build                 # debug build
swift test                  # run the tests
Scripts/build-app.sh        # build and sign .build/Sorla.app
Scripts/release.sh          # build a signed DMG in .build/release-artifacts
```

`Scripts/build-app.sh` signs with the hardened runtime, using the first Apple Development identity in your keychain, or ad hoc if there is none. Set `SORLA_SIGN_IDENTITY` to choose another identity.

`Scripts/release.sh` signs with a Developer ID Application identity when one is available and falls back to Apple Development. With a Developer ID identity, `SORLA_NOTARIZE=1 Scripts/release.sh` also notarizes and staples the DMG. Notarizing reads your App Store Connect API key details from `~/.config/sorla/release.env`, outside the repository; copy `Scripts/release.env.example` there and fill it in.

## License

Sorla is open source under the [Apache License 2.0](LICENSE). Copyright 2026 Anders Markström.

Third-party components keep their own licenses, which are included in [`Resources/Licenses`](Resources/Licenses) and shipped with the app:

| Component | License |
|---|---|
| Klang Pianissimo (Klang AI AB), based on NVIDIA Parakeet TDT 0.6B v3 | [CC BY 4.0](Resources/Licenses/Pianissimo.txt) |
| FluidAudio | [Apache-2.0](Resources/Licenses/FluidAudio/LICENSE) |
| KeyboardShortcuts | [MIT](Resources/Licenses/KeyboardShortcuts/LICENSE) |
