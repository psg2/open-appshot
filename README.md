# Open AppShot

Open AppShot captures the last active macOS window as pixels and Accessibility context. It keeps a local history and writes both representations to the clipboard for use in any chat or agent UI.

Version 0.3.2 installs as `Open AppShot.app`, adds keyboard commands for capture history, and lets the user choose whether deletion needs confirmation. Its global shortcut and confirmation sound are configurable, and Command-W closes the window without quitting the capture service. The app remains capture-only. It cannot click, type, scroll, or invoke UI actions.

The installed bundle and executable are named Open AppShot. The app keeps the legacy bundle identifier `com.psg2.AppShotClipboardPOC` so macOS can reuse permissions granted to the prototype.

## Requirements

- macOS 15 or later
- Xcode command-line tools with Swift
- Peekaboo 4.2.2 or a compatible release

Install Peekaboo from its official Homebrew tap:

```sh
brew tap steipete/tap
brew install steipete/tap/peekaboo
```

## Build and install

```sh
make build
make smoke
make install
```

`make smoke` launches a deterministic local fixture and captures it through the built command-line entry point. It checks the PNG, Accessibility JSON, history metadata, private file permissions, local Peekaboo runtime, and multipart clipboard contract.

After installation, exercise the real global-hotkey path:

```sh
make hotkey-smoke
```

## First run

1. Open `/Applications/Open AppShot.app`.
2. In the permission banner or Settings, choose **Request Missing Permissions**.
3. Enable Open AppShot under System Settings > Privacy & Security > Accessibility and Screen & System Audio Recording.
4. Quit and reopen the app if macOS requests it.
5. Focus the window you want to share.
6. Press **Left Option + Right Option** together, or use the shortcut configured in Settings.

The capture appears at the top of the history and is copied to the clipboard by default. The Codex desktop app already owns Left Command + Right Command, so Open AppShot defaults to the two Option keys to avoid triggering both apps.

## Native app

The main window has a capture filmstrip on the left and two previews on the right:

- **Screenshot** shows the exact window pixels.
- **Accessibility** shows the readable, redacted AX summary.

The context rail under the preview reports the image dimensions, AX element count, and storage source. The toolbar can capture the last active window, reload history, copy either representation, reveal the capture in Finder, or delete it. Hover or select a capture in the sidebar to reveal its delete button. By default, Enter confirms the deletion dialog and Escape cancels it.

Open AppShot lives in the menu bar instead of the Dock. Command-W closes its current window while leaving the global shortcut active. Use the menu bar icon to reopen the history, capture immediately, or open Settings.

The Capture menu exposes the window commands and their shortcuts:

- Shift-Command-C captures the last active window;
- Option-Command-C copies the selected screenshot and context;
- Option-Command-I copies the selected screenshot;
- Option-Command-T copies the selected Accessibility context;
- Shift-Command-R reveals the selected capture in Finder;
- Command-R reloads the history;
- Delete asks to remove the selected capture.

Open Settings with Command-comma to:

- inspect both macOS permissions;
- record a custom global shortcut or restore the two-Option default;
- choose or disable the confirmation sound and preview it;
- choose a capture folder;
- keep captures for 1, 7, 30, or 90 days, or forever;
- choose whether Delete and the trash button ask for confirmation;
- control automatic clipboard copy.

## Storage and privacy

New captures go to:

```text
~/Library/Application Support/Open AppShot/Captures/<capture-id>/
```

The app keeps showing captures from the default folder after you choose a custom destination. It also shows captures left by the original POC under `/tmp/AppShotClipboardPOC` until macOS clears them. Choosing a destination affects new captures only.

Each capture contains:

- `screenshot.png`
- `thumbnail.png`
- `accessibility.json`
- `context.md`
- `metadata.json`
- local Peekaboo diagnostics

Directories use mode `0700` and files use `0600`. Secure Accessibility values are redacted. Open AppShot does not use OCR, AI providers, telemetry, or network upload. A screenshot can still contain anything visibly present in the selected window.

## Clipboard contract

One pasteboard item carries:

- `public.png`, the exact window screenshot;
- `public.utf8-plain-text`, a readable Accessibility summary;
- `com.psg2.appshot-context-json`, sanitized structured data for future adapters.

The receiving chat chooses which representation it imports. Some composers accept the image and ignore the text. Use the capture actions to copy the screenshot and Accessibility context separately when needed.

## Repository layout

```text
Sources/OpenAppShot/AppModel.swift  History, permissions, storage, and UI state
Sources/OpenAppShot/Views.swift     Native SwiftUI windows and settings
Sources/OpenAppShot/main.swift      Capture engine, clipboard, menu bar, and hotkey
Resources/Info.plist                Bundle identity and permission descriptions
Scripts/                            Build, install, and observable smoke tests
Tests/Fixtures/                     Deterministic capture target
Tests/Support/                      Synthetic configurable-hotkey event
docs/                               Architecture and prototype findings
```

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the current boundaries and [docs/PROTOTYPE-VERDICT.md](docs/PROTOTYPE-VERDICT.md) for the original experiment results.

## Current project status

- Local repository only. No Git remote is configured.
- No open-source license has been selected.
- Local builds use an ad hoc signature with a stable identifier-only designated requirement.
- Public distribution still needs Developer ID signing and notarization.
