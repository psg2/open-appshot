# Current architecture

## Scope

Open AppShot 0.3.0 observes the last active macOS window after a user gesture. It stores and displays the resulting pixels and Accessibility context. It cannot act on the captured UI.

## App structure

```text
AppKit lifecycle and global hotkey
  -> AppModel observable state
  -> SwiftUI NavigationSplitView and Settings window

CaptureEngine
  -> local Peekaboo process
  -> private capture bundle
  -> capture history
  -> multipart NSPasteboard item
```

`main.swift` retains the AppKit lifecycle because it owns the accessory-app activation policy, status item, main menu, global keyboard monitors, command-line smoke-test entry points, and background capture process. `AppModel.swift` owns user-visible state and preferences. `Views.swift` renders the main and Settings windows with SwiftUI.

## Capture path

```text
Configured global hotkey or Capture
  -> last external NSRunningApplication
  -> Peekaboo local window inventory
  -> exact-window screenshot and Accessibility observation
  -> split screenshot and AX fallback when combined observation fails
  -> secure-field redaction
  -> metadata and local capture bundle
  -> history refresh
  -> multipart NSPasteboard item when auto-copy is enabled
```

Peekaboo commands always use `--no-remote`. Pixel capture also selects `--capture-engine cg`. TCC responsibility stays with Open AppShot instead of moving to an on-demand Peekaboo daemon.

## Capture storage

The default root is `~/Library/Application Support/Open AppShot/Captures`. The user can choose another folder in Settings. Retention runs before each capture and supports 1, 7, 30, or 90 days, or no automatic deletion.

Each capture directory contains:

- `screenshot.png`
- `thumbnail.png`
- `accessibility.json`
- `context.md`
- `metadata.json`
- window inventory and diagnostic output

The directory uses mode `0700`; files use `0600`. `metadata.json` is the stable history index. A 320-pixel thumbnail keeps the history sidebar from decoding every full screenshot on launch. The history loader can derive enough metadata from older `context.md` files to display POC captures under `/tmp/AppShotClipboardPOC` without modifying them.

## UI state

`AppModel` scans the configured capture root, the default root when a custom destination is active, and the legacy POC root. It keeps the current selection, permission status, capture progress, storage location, retention, sound, hotkey, and clipboard preferences. A completed hotkey capture refreshes history and selects the new record.

The native UI has four visible boundaries:

- the history sidebar with local thumbnails and confirmed direct deletion;
- the screenshot and Accessibility previews;
- the context rail with pixel, AX, and storage facts;
- Settings for permissions, hotkey recording, sound, capture behavior, retention, and destination.

## Clipboard boundary

The same pasteboard item advertises PNG, UTF-8 text, and sanitized JSON. A receiving chat may select only one representation. The history actions can copy the image or context separately without recapturing the window.

## Permissions and signing

Accessibility permission covers the global keyboard monitor and AX inspection. Screen Recording permission covers pixels. The main window and Settings show both states and link to the corresponding System Settings panes.

The app uses the accessory activation policy and `LSUIElement` so it appears in the menu bar without a permanent Dock icon. Closing a window does not release its controller or terminate the process, which keeps the status item and hotkey available.

Local builds are ad hoc signed with an identifier-only designated requirement. The requirement stays stable across rebuilds but does not provide production-grade identity. Public distribution requires Developer ID signing and notarization.

## Decisions still open

- Final `.app` filename and migration of the installed prototype
- Developer ID ownership and release signing
- License
- Supported Peekaboo version range
- Clipboard behavior in each target chat client
- Per-app deny rules and visible screenshot redaction
- Whether to depend on Peekaboo or extract a smaller observation-only component
