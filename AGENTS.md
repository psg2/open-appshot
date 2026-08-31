# Project working agreements

- Keep the product capture-only unless a separate design decision explicitly authorizes UI actions.
- Preserve `com.psg2.AppShotClipboardPOC` while the local TCC migration remains open.
- Keep code and comments in English.
- Test observable behavior through the built app or its command-line entry point.
- Run `make check` before handing off code and the permission-dependent smoke tests when capture behavior changes.
- Do not add a public license, Git remote, release workflow, telemetry, or network upload without an explicit decision.
- Treat screenshots and Accessibility output as sensitive local data.
