# Open AppShot

Open AppShot is a local macOS experiment for capturing the frontmost window as pixels and Accessibility context, then placing both representations on the clipboard.

The current product name remains `AppShot Clipboard POC.app`. Keeping its bundle ID stable avoids invalidating the macOS permissions already granted during the prototype. The repository name is the working project name; renaming the app is a separate migration.

## Status

- Local repository only. No Git remote is configured.
- Prototype version: 0.1.1.
- No open-source license has been selected yet.
- Capture-only. The app cannot click, type, scroll, or invoke UI actions.

## Requirements

- macOS 15 or later
- Xcode command-line tools with Swift
- Peekaboo 4.2.2 or a compatible release

Install Peekaboo from its official Homebrew tap:

```sh
brew tap steipete/tap
brew install steipete/tap/peekaboo
```

## Build and test

```sh
make build
make smoke
```

`make smoke` launches a deterministic local fixture and captures it through the built command-line entry point. It checks the PNG, Accessibility JSON, text summary, private file permissions, local Peekaboo runtime, and multipart clipboard contract.

To install the current build in `/Applications` and run the menu-bar app:

```sh
make install
```

After granting Accessibility and Screen & System Audio Recording permission, exercise the real global-hotkey path:

```sh
make hotkey-smoke
```

## Use the app

1. Open `/Applications/AppShot Clipboard POC.app`.
2. Open the menu-bar camera and choose **Request missing permissions** once.
3. Enable the app under System Settings > Privacy & Security > Accessibility and Screen & System Audio Recording, then quit and reopen it.
4. Focus the window you want to share.
5. Press **Left Option + Right Option** together.
6. Wait for the confirmation sound, then paste into the chat.

The Codex desktop app already owns Left Command + Right Command. Reusing that gesture would trigger both apps.

## Clipboard contract

One pasteboard item carries:

- `public.png`, the exact window screenshot;
- `public.utf8-plain-text`, a readable Accessibility summary;
- `com.psg2.appshot-context-json`, sanitized structured data for future adapters.

The receiving chat chooses which representation it imports. Some chat composers accept the image and ignore the text. The menu-bar app can copy the screenshot and Accessibility text separately without capturing again.

## Files and privacy

Each capture is stored under `/tmp/AppShotClipboardPOC/<capture-id>/`. Directories use mode `0700`, files use `0600`, and the helper removes capture directories older than 24 hours. Secure Accessibility field values are redacted.

The app does not use OCR, AI providers, network upload, click, type, or scroll. The screenshot can still contain anything visibly present in the selected window. The user-triggered hotkey is the privacy boundary.

## Repository layout

```text
Sources/OpenAppShot/main.swift     Menu-bar app and capture pipeline
Resources/Info.plist               Bundle identity and permission descriptions
Scripts/build.sh                   Build and stable prototype signing
Scripts/install-local.sh           Install the built app in /Applications
Scripts/smoke-test.sh              Finder capture contract
Scripts/hotkey-smoke-test.sh       Installed app and global-hotkey contract
Tests/Support/TriggerHotkey.swift  Synthetic two-Option test event
Tests/Fixtures/                    Deterministic capture target
docs/                              Architecture and prototype findings
```

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the current boundaries and [docs/PROTOTYPE-VERDICT.md](docs/PROTOTYPE-VERDICT.md) for the original experiment results.

## Signing note

Prototype builds use an ad hoc signature with a stable identifier-only designated requirement. This avoids a new TCC prompt after every local rebuild, but it is weaker than Developer ID signing. Before distribution, replace it with Developer ID signing and notarization.
