# Project working agreements

- Keep the product capture-only unless a separate design decision explicitly authorizes UI actions.
- Preserve `com.psg2.AppShotClipboardPOC` while the local TCC migration remains open.
- Keep code and comments in English.
- Keep capture, storage, and clipboard logic in `OpenAppShotCore` and presentation in the `OpenAppShot` app target.
- Test observable behavior through the `OpenAppShotCore` interface, the built app, or its command-line entry point. Do not assert internal call order or source text.
- Run `mise run check` before handing off code and the permission-dependent smoke tests when capture behavior changes.
- Do not add telemetry or network upload without an explicit decision.
- Open pull requests ready for review in English, explaining why, what changed, validation, and limitations. Monitor checks and bot review comments.
- Use standard GitHub-hosted runners. Keep write permissions limited to the release job, pin actions by full commit SHA, and never publish local credentials.
- Release by pushing a `vX.Y.Z` tag that matches `VERSION`; update `docs/release-notes.md` first.
- Treat screenshots and Accessibility output as sensitive local data.
