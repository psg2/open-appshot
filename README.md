# Open AppShot

Open AppShot captures the last active macOS window as pixels and Accessibility context. It keeps a local history and writes both representations to the clipboard for use in any chat or agent UI.

Version 0.4.0 installs as `Open AppShot.app` with configurable clipboard modes, its own capture-and-accessibility icon, keyboard commands for capture history, and a configurable deletion confirmation. Its global shortcut and confirmation sound are configurable, and Command-W closes the window without quitting the capture service. The app remains capture-only. It cannot click, type, scroll, or invoke UI actions.

The installed bundle and executable are named Open AppShot. The app keeps the legacy bundle identifier `com.psg2.AppShotClipboardPOC` so macOS can reuse permissions granted to the prototype.

## Requirements

- macOS 15 or later
- Full Xcode with Swift
- [mise](https://mise.jdx.dev/) for pinned repository tools

Install the repository quality tools:

```sh
make setup
```

## Build and install

```sh
make build
make smoke
make install
```

`make smoke` launches a deterministic local fixture and captures it through the native ScreenCaptureKit and Accessibility adapter. It checks the PNG, Accessibility JSON, history metadata, private file permissions, and every clipboard mode. Peekaboo is no longer required; developers who already have it can run `make smoke-engines` to compare both adapters.

After installation, exercise the real global-hotkey path:

```sh
make hotkey-smoke
```

## Development quality gates

Install the same local tools used by CI and enable the pre-push hook:

```sh
make setup
make hooks
```

The main commands are:

```sh
make format        # rewrite Swift sources with swift-format
make lint          # swift-format, ShellCheck, actionlint, and plist checks
make test          # CI-safe bundle and command-line contract tests
make scan-secrets  # full-history Gitleaks scan
make check         # all publication gates above
```

`make test` does not need Accessibility or Screen Recording access. The capture and global-hotkey smoke tests remain local because GitHub-hosted runners cannot grant those macOS permissions.

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
- Option-Command-C copies the selected capture using the configured clipboard mode;
- Option-Command-I copies the selected screenshot;
- Option-Command-T copies the selected Accessibility context;
- Shift-Command-R reveals the selected capture in Finder;
- Command-R reloads the history;
- Delete asks to remove the selected capture.

Open Settings with Command-comma to:

- inspect both macOS permissions;
- select the native engine or the optional Peekaboo comparison adapter;
- record a custom global shortcut or restore the two-Option default;
- choose or disable the confirmation sound and preview it;
- choose a capture folder;
- keep captures for 1, 7, 30, or 90 days, or forever;
- choose whether Delete and the trash button ask for confirmation;
- control automatic clipboard copy and choose its content.

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
- native window inventory or optional Peekaboo diagnostics

Directories use mode `0700` and files use `0600`. Secure Accessibility values are redacted. Open AppShot does not use OCR, AI providers, telemetry, or network upload. A screenshot can still contain anything visibly present in the selected window.

## Clipboard modes

The selected clipboard mode controls automatic copies and the main Copy command:

- **Image + Full Accessibility** writes `public.png`, readable text for every captured element, and redacted structured JSON under `com.psg2.appshot-context-json`.
- **Image + File References** writes `public.png` and compact text with absolute local paths to `screenshot.png`, `accessibility.json`, and `context.md`. It does not place the full Accessibility content on the clipboard.
- **Image Only** writes `public.png` without text or Accessibility JSON.
- **Accessibility Only** writes the readable text and structured JSON without image pixels.

One pasteboard item advertises all representations for the selected mode. A receiving chat may still choose only one representation. The explicit image-only and Accessibility-only capture actions remain available without changing Settings.

## Repository layout

```text
Sources/OpenAppShot/AppModel.swift  History, permissions, storage, and UI state
Sources/OpenAppShot/Views.swift     Native SwiftUI windows and settings
Sources/OpenAppShot/ObservationEngine.swift  Shared observation interface and models
Sources/OpenAppShot/NativeObservationEngine.swift  ScreenCaptureKit and AX adapter
Sources/OpenAppShot/PeekabooObservationEngine.swift  Optional comparison adapter
Sources/OpenAppShot/main.swift      Capture storage, clipboard, menu bar, and hotkey
Resources/Info.plist                Bundle identity and permission descriptions
Resources/AppIcon.png               1024-pixel source for the native app icon
CONTEXT.md                           Canonical capture and clipboard vocabulary
Scripts/                            Build, install, and observable smoke tests
Tests/Fixtures/                     Deterministic capture target
Tests/Support/                      Synthetic configurable-hotkey event
docs/                               Architecture and prototype findings
.github/workflows/ci.yml            Secret scanning and macOS quality gates
mise.toml                           Pinned local and CI quality tools
lefthook.yml                        Local pre-push quality gates
```

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the current boundaries, [docs/PROTOTYPE-VERDICT.md](docs/PROTOTYPE-VERDICT.md) for the original experiment results, and [docs/RELEASING.md](docs/RELEASING.md) for the publication checklist.

## Current project status

- CI, local hooks, formatting, linting, contract tests, Gitleaks, issue templates, and security guidance are ready.
- The repository is still local; no Git remote is configured.
- No open-source license has been selected, so the code is not ready to be published as open source yet.
- Local builds use an ad hoc signature with a stable identifier-only designated requirement.
- Public binary distribution still needs Developer ID signing, hardened-runtime review, and notarization.
