# Current architecture

## Scope

Open AppShot 0.5.0 observes the last active macOS window after a user gesture. It stores and displays the resulting pixels and Accessibility context. It cannot act on the captured UI.

## App structure

```text
AppKit lifecycle and global hotkey
  -> AppModel observable state
  -> SwiftUI NavigationSplitView and Settings window

CaptureEngine
  -> NativeObservationEngine
       -> ScreenCaptureKit exact-window pixels
       -> bounded macOS Accessibility traversal
  -> private capture bundle
  -> capture history
  -> multipart NSPasteboard item
```

`main.swift` retains the AppKit lifecycle because it owns the accessory-app activation policy, status item, main menu, global keyboard monitors, command-line smoke-test entry points, and background capture process. `AppModel.swift` owns user-visible state and preferences. `Views.swift` renders the main and Settings windows with SwiftUI.

## Capture path

```text
Configured global hotkey or Capture
  -> last external NSRunningApplication
  -> NativeObservationEngine
  -> exact-window screenshot and bounded Accessibility observation
  -> secure-field redaction
  -> metadata and local capture bundle
  -> history refresh
  -> configured NSPasteboard representations when auto-copy is enabled
```

The native capture uses public ScreenCaptureKit and Accessibility APIs directly. Single-window shadows are disabled before capture so the window fills the configured native-resolution canvas instead of being scaled down inside transparent padding. The smoke test asserts the output dimensions and opaque canvas coverage. TCC responsibility stays with Open AppShot.

## Capture storage

The default root is `~/Library/Application Support/Open AppShot/Captures`. A custom destination always receives an app-owned `Open AppShot/Captures` child rather than becoming a capture root itself. The preferences registry retains every 0.5-or-later root selected by the user. History and retention include all registered roots. Retention runs before each capture and supports 1, 7, 30, or 90 days, or no automatic deletion. It prunes only direct children with a valid ownership marker or a strict legacy capture layout; unrelated directories and symbolic links are ignored.

Each capture directory contains:

- `screenshot.png`
- `thumbnail.png`
- `accessibility.json`
- `context.md`
- `metadata.json`
- `.open-appshot-capture` ownership marker
- selected-window diagnostic output

The directory uses mode `0700`; files use `0600`. `metadata.json` is the stable history index. A 320-pixel thumbnail keeps the history sidebar from decoding every full screenshot on launch. New captures are assembled under a hidden staging directory and atomically renamed only after all files and permissions are complete. A later capture removes app-marked staging directories left by a crash after one hour, even when history retention is disabled. The history loader requires an ownership marker or a strict AppShot directory name, metadata ID, context header, screenshot, and AX JSON before it permits deletion. Recognized metadata-less POC captures are read-only. Arbitrary legacy custom roots never receive automatic retention cleanup.

## UI state

`AppModel` scans the configured capture root, the default root when a custom destination is active, and the legacy POC root. It keeps the current selection, deletion policy, pending deletion, permission status, capture progress, storage location, retention, sound, hotkey, automatic-copy policy, and clipboard mode. A completed hotkey capture refreshes history and selects the new record.

The native UI has four visible boundaries:

- the history sidebar with local thumbnails and configurable direct deletion;
- the screenshot and Accessibility previews;
- the context rail with pixel, AX, and storage facts;
- Settings for permissions, hotkey recording, sound, clipboard content, capture behavior, retention, deletion confirmation, and destination.

## Clipboard boundary

`ClipboardMode` selects one fixed set of pasteboard representations. Full Accessibility mode advertises PNG, UTF-8 text for every collected element, and sanitized JSON. Reference mode advertises PNG plus compact local paths without embedding the AX content. Image-only and Accessibility-only modes omit the other side entirely. A receiving chat may select only one advertised representation. The explicit history actions can still copy pixels or context separately without recapturing the window.

## Permissions and signing

Accessibility permission covers the global keyboard monitor and AX inspection. Screen Recording permission covers pixels. The main window and Settings show both states and link to the corresponding System Settings panes.

The app uses the accessory activation policy and `LSUIElement` so it appears in the menu bar without a permanent Dock icon. Closing a window does not release its controller or terminate the process, which keeps the status item and hotkey available.

Local builds install as `/Applications/Open AppShot.app` with a universal `OpenAppShot` executable targeting macOS 15. The legacy `com.psg2.AppShotClipboardPOC` bundle identifier remains while the TCC migration is open. The installer removes the old POC-named bundle after it verifies the renamed app.

Local builds use the default ad hoc designated requirement, which is tied to their code hashes. The build has no identifier-only override. The release packager requires a Developer ID Application identity, enables hardened runtime, builds both architectures, submits the archive for notarization, staples the ticket, verifies Gatekeeper, and writes a checksum.

The repository keeps the prototype bundle identifier while the migration remains open. A machine that granted TCC access to the old identifier-only build must explicitly run `./Scripts/uninstall-local.sh --reset-permissions` and grant access again to the Developer ID build. Installation never revokes permissions without the user's request.

## Decisions still open

- Developer ID ownership and release signing
- Git remote and repository service activation
- Clipboard representation selection in each target chat client
- Per-app deny rules and visible screenshot redaction

The source-level assessment that led to the native adapter is documented in
[PEEKABOO-DEPENDENCY-ASSESSMENT.md](PEEKABOO-DEPENDENCY-ASSESSMENT.md).
