# Prototype verdict

## Question

Can one global hotkey capture the frontmost macOS window as both pixels and Accessibility context, then make that context available to unrelated chat UIs through the clipboard?

## Answer

Yes for capture and transport. The prototype registered Left Option + Right Option globally, selected the target app and key window, captured a PNG and AX tree, sanitized the structured context, and wrote image, text, and JSON representations to one pasteboard item.

The remaining incompatibility belongs to each receiving chat. macOS lets a clipboard item advertise several representations, but a consumer may choose only one. There is no universal clipboard format that forces every chat composer to import both an image attachment and text in one paste operation.

The practical UX is:

1. One hotkey captures once and copies the multipart item.
2. One paste works when the chat supports the desired representation.
3. Menu-bar actions reuse the same capture for separate image and text pastes when the chat chooses only one.

## Evidence from this machine

- Peekaboo 4.2.2 has Screen Recording, Accessibility, and event-synthesis permissions.
- Finder capture returned a 51,515-byte PNG and 207 AX elements.
- Orca capture returned a 258,125-byte PNG and 12 AX elements.
- A global synthetic Left Option + Right Option event captured ChatGPT with 107 AX elements.
- Helium rejected Peekaboo's combined exact-window observation. The read-only split fallback recovered a valid screenshot and 264 AX elements.
- The final clipboard simultaneously advertised PNG, UTF-8 text, TIFF compatibility types, and the custom sanitized JSON type.

## Historical product decision

Do not build a new screen-capture and Accessibility engine. Keep Peekaboo as the signed capture host. If this moves beyond a prototype, build a small notarized helper around the validated contract, add configurable hotkeys and per-app deny rules, and test paste behavior in the exact chat clients that matter.

This decision described the first-day prototype and is now superseded. Open AppShot now captures directly through public ScreenCaptureKit and Accessibility APIs. Peekaboo was retained briefly for deterministic comparison and removed after the native path matched its 1040 x 624 output, opaque canvas coverage, and eight-element AX result.

## Permission bug found during use

The original 0.1.0 build selected Peekaboo's on-demand daemon. That daemon later restarted without Screen Recording or Accessibility permission, so the hotkey fired but `window list` failed. The helper also used an ad hoc signature whose designated requirement was its changing code hash. Rebuilds left a stale enabled row in System Settings and triggered a new permission prompt.

Version 0.1.1 forces Peekaboo local execution with the CG capture engine, reports the helper's own TCC state, stops automatic permission prompting, and signs each prototype build with the same identifier-only designated requirement. A production build still needs Developer ID signing and notarization.
