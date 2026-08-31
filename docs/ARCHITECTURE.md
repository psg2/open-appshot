# Current architecture

## Scope

Open AppShot observes the frontmost macOS window after a user gesture. Version 0.1.1 cannot act on the captured UI.

## Capture path

```text
Left Option + Right Option
  -> frontmost NSRunningApplication
  -> Peekaboo local window inventory
  -> exact-window screenshot and Accessibility observation
  -> split screenshot and AX fallback when combined observation fails
  -> secure-field redaction
  -> local capture bundle
  -> multipart NSPasteboard item
```

Peekaboo commands always use `--no-remote`. Pixel capture also selects `--capture-engine cg`. This avoids permission drift in an on-demand Peekaboo daemon and keeps TCC responsibility with the menu-bar app.

## Capture bundle

Each capture lives under `/tmp/AppShotClipboardPOC/<capture-id>/` for at most 24 hours. The bundle contains:

- `screenshot.png`
- `accessibility.json`
- `context.md`
- window inventory and diagnostic output

The directory uses mode `0700`; files use `0600`.

## Clipboard boundary

The same pasteboard item advertises PNG, UTF-8 text, and sanitized JSON. A receiving chat may select only one representation. The menu-bar app keeps the last capture available for separate image and text copies.

## Permissions and signing

The app needs Accessibility for the two-Option global monitor and AX inspection. It needs Screen Recording for pixels.

Local builds are ad hoc signed with an identifier-only designated requirement. That requirement stays stable across rebuilds but does not provide production-grade code identity. Public distribution requires Developer ID signing and notarization.

## Decisions still open

- Final product name, bundle ID, and migration of existing TCC permissions
- Developer ID ownership and release signing
- License
- Supported macOS and Peekaboo version range
- Clipboard behavior in each target chat client
- Per-app deny rules and visible redaction policy
- Whether to depend on Peekaboo or extract a smaller observation-only component
