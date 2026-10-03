# Project working agreements

- Keep the product capture-only unless a separate design decision explicitly authorizes UI actions.
- Preserve `com.psg2.AppShotClipboardPOC` while the local TCC migration remains open.
- Keep code and comments in English.
- Keep capture, storage, and clipboard logic in `OpenAppShotCore` and presentation in the `OpenAppShot` app target.
- Test observable behavior through the `OpenAppShotCore` interface, the built app, or its command-line entry point. Do not assert internal call order or source text.
- Run `make check` before handing off code and the permission-dependent smoke tests when capture behavior changes.
- Do not add a public license, Git remote, release workflow, telemetry, or network upload without an explicit decision.
- Treat screenshots and Accessibility output as sensitive local data.
