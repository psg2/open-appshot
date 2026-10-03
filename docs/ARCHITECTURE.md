# Architecture

Open AppShot observes one window after a user gesture and stores what it saw. It never acts on the captured UI.

## Layout

```text
Sources/OpenAppShotCore/      capture pipeline, observation, storage, history, preferences, clipboard
Sources/OpenAppShot/          entry point, command-line interface, menu bar, SwiftUI windows
Tests/OpenAppShotCoreTests/   unit tests for the library
Tests/Fixtures/, Support/     capture target and synthetic shortcut for the smoke tests
Scripts/                      build, install, release, and test scripts
```

## Capture path

A capture follows this path:

1. The shortcut or Capture command picks the last active app that isn't Open AppShot.
2. `NativeObservationEngine` lists that app's windows through ScreenCaptureKit and pairs one with an Accessibility window using `WindowMatching`.
3. It captures the window without its shadow and walks the Accessibility tree. The walk stops at 1,500 elements, depth 20, or 4 seconds.
4. `CaptureEngine` writes the files to a staging folder, sets permissions, and moves the folder into the history.
5. `ClipboardWriter` copies the representations for the selected clipboard mode.

`WindowMatching` accepts a pair when the frames' intersection over union is at least 0.80, or 0.50 when the titles match, and only when the best candidate leads the runner-up by 0.15. If the focused Accessibility window matches no screen window, the engine uses the app's single active window and fails the capture when there are several. If no Accessibility window matches the captured window, the Accessibility output is marked incomplete. The engine never substitutes another window.

## Storage rules

- New captures are assembled in a hidden `.staging-<uuid>` folder and renamed into the history only after every file and permission is in place. A failed capture deletes its staging folder. Staging folders older than one hour, left by a crash, are removed on the next capture.
- Retention runs before each capture over every capture root the user has selected. It removes only direct children that carry a valid `.open-appshot-capture` marker or the exact legacy layout, whose `metadata.json` id must match the folder name. It skips symbolic links and unrelated folders.
- The history loader shows legacy prototype captures read-only when it can't verify ownership.

## Clipboard

`ClipboardWriter` puts every representation of the selected mode on one `NSPasteboardItem`: PNG, UTF-8 text, and the redacted JSON under `com.psg2.appshot-context-json`. The receiving app chooses which types it reads.

## Permissions and signing

Accessibility covers the global keyboard monitor and the tree walk. Screen Recording covers the pixels. The app runs as an accessory with `LSUIElement`, so it has a menu bar item and no permanent Dock icon. Closing a window keeps the process, the menu bar item, and the shortcut alive.

The bundle keeps the prototype identifier `com.psg2.AppShotClipboardPOC`. Local and release builds are ad hoc signed, so macOS ties permission grants to each binary's code hash. `Scripts/package-release.sh` also supports Developer ID signing with notarization; see [RELEASING.md](RELEASING.md).
