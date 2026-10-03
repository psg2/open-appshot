# Open AppShot

Open AppShot captures the last active macOS window as pixels and Accessibility context. It keeps a local history and writes both representations to the clipboard for use in any chat or agent UI.

Version 0.5.0 installs as a universal `Open AppShot.app` for Apple Silicon and Intel Macs. It has configurable clipboard modes, global and in-app shortcuts, capture history, safe retention, and a configurable deletion confirmation. Command-W closes the window without quitting the capture service. The app remains capture-only. It cannot click, type, scroll, or invoke UI actions.

The installed bundle and executable are named Open AppShot. The app currently keeps the legacy bundle identifier `com.psg2.AppShotClipboardPOC`. A Mac that granted permissions to an early identifier-only development build must reset those grants before using a distributable Developer ID build; see [Reset migrated permissions](#reset-migrated-permissions).

## Requirements

- macOS 15 or later
- Xcode 16 or later with Swift
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

`make smoke` launches a deterministic local fixture behind normal windows and captures it through ScreenCaptureKit and Accessibility. It checks that the window fills the PNG without shadow padding, then verifies the Accessibility JSON, history metadata, private file permissions, and every clipboard mode. Peekaboo is not required.

The fixture runs behind normal windows without a Dock icon and is removed when the test exits. It is never included in the application bundle. Local ad hoc builds use their code hash as identity; the repository does not offer an identifier-only signing mode.

After installation, exercise the real global-hotkey path:

```sh
make hotkey-smoke
```

`make hotkey-smoke` installs the current sources before exercising the global shortcut, so it cannot pass against a stale app in `/Applications`.

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
- record a custom global shortcut or restore the two-Option default;
- choose or disable the confirmation sound and preview it;
- choose a capture folder;
- keep captures for 1, 7, 30, or 90 days, or forever;
- choose whether Delete and the trash button ask for confirmation;
- control automatic clipboard copy and choose its content.

## Storage and privacy

Default captures go to:

```text
~/Library/Application Support/Open AppShot/Captures/<capture-id>/
```

When you choose a custom destination, Open AppShot creates its own `Open AppShot/Captures` subdirectory beneath it. The app remembers every 0.5-or-later capture root you selected, keeps those captures in history, and applies retention to each root. Retention never deletes arbitrary children of the folder you selected: it removes only validated Open AppShot capture directories. The app also shows captures from the default folder and strictly recognized POC locations. Unverified legacy items are read-only.

Each capture contains:

- `screenshot.png`
- `thumbnail.png`
- `accessibility.json`
- `context.md`
- `metadata.json`
- `.open-appshot-capture` ownership marker
- selected-window diagnostic metadata

Directories use mode `0700` and files use `0600`. Secure Accessibility values are redacted. If the captured ScreenCaptureKit window cannot be confidently paired with an Accessibility window, AX output is marked incomplete instead of falling back to another window or the entire application. Open AppShot does not use OCR, AI providers, telemetry, or network upload. A screenshot can still contain anything visibly present in the selected window.

Captures are written to a hidden staging directory and moved into history only after every required file is complete. A failed capture removes its staging data instead of leaving a hidden screenshot behind.

## Uninstalling

The default uninstall keeps captures, preferences, and permissions:

```bash
make uninstall
```

Removal of sensitive data and TCC grants is explicit:

```bash
./Scripts/uninstall-local.sh --data
./Scripts/uninstall-local.sh --preferences
./Scripts/uninstall-local.sh --reset-permissions
./Scripts/uninstall-local.sh --all
```

The script stops the capture service before changing app state. `--data` removes only capture directories with verified Open AppShot ownership from known roots and the fixed POC temporary directory. It preserves unrelated files even inside those roots and never recursively removes the arbitrary custom root used by older versions.
Run `make build` first if no current build exists; data removal never delegates ownership checks to a potentially old installed binary.

## Reset migrated permissions

Early local builds used an identifier-only ad hoc requirement. If this Mac granted Accessibility or Screen Recording to one of those builds, reset the old grants before trusting a Developer ID release:

```bash
./Scripts/uninstall-local.sh --reset-permissions
```

Open the signed app afterward and grant both permissions again. This reset is intentionally never run during installation.

## Clipboard modes

The selected clipboard mode controls automatic copies and the main Copy command:

- **Image + Full Accessibility** writes `public.png`, readable text for every captured element, and redacted structured JSON under `com.psg2.appshot-context-json`.
- **Image + File References** writes `public.png` and compact text with absolute local paths to `screenshot.png`, `accessibility.json`, and `context.md`. It does not place the full Accessibility content on the clipboard.
- **Image Only** writes `public.png` without text or Accessibility JSON.
- **Accessibility Only** writes the readable text and structured JSON without image pixels.

One pasteboard item advertises all representations for the selected mode. A receiving chat may still choose only one representation. The explicit image-only and Accessibility-only capture actions remain available without changing Settings.

## Repository layout

```text
Package.swift                       Swift package manifest used by Scripts/build.sh
Sources/OpenAppShot/main.swift      Entry point: command-line commands, then the app
Sources/OpenAppShot/AppDelegate.swift  Menu bar, main menu, and global hotkey
Sources/OpenAppShot/CommandLineInterface.swift  Command-line contract used by scripts and tests
Sources/OpenAppShot/CaptureEngine.swift  Capture pipeline, staging, and context text
Sources/OpenAppShot/ClipboardWriter.swift  Clipboard modes and pasteboard output
Sources/OpenAppShot/NativeObservationEngine.swift  ScreenCaptureKit and AX capture
Sources/OpenAppShot/ObservationModels.swift  Native observation result models
Sources/OpenAppShot/CaptureStorage.swift  Capture ownership and safe retention
Sources/OpenAppShot/CaptureHistory.swift  History loading, including legacy captures
Sources/OpenAppShot/CapturePreferences.swift  User defaults and storage roots
Sources/OpenAppShot/CaptureHotkey.swift  Hotkey model and validation
Sources/OpenAppShot/AppModel.swift  Observable UI state and actions
Sources/OpenAppShot/Views.swift     Native SwiftUI windows and settings
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
- The source is available under the MIT License.
- The repository is still local; no Git remote is configured.
- Normal local builds use a code-hash-bound ad hoc identity. The repository has no weak identifier-only signing mode.
- `make package-release` provides a fail-closed universal Developer ID, hardened-runtime, notarization, stapling, versioned archive, and portable checksum path once signing credentials are configured.
