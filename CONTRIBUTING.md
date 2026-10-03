# Contributing

Thanks for helping improve Open AppShot. The project is intentionally capture-only: it observes a selected window but does not click, type, scroll, or invoke UI actions.

## Development setup

You need macOS 15 or later and Xcode 16 or later. Install the repository tools and Git hooks:

```bash
mise install
mise run hooks
```

`mise install` uses the checked-in `mise.toml` to install pinned versions of Gitleaks, ShellCheck, actionlint, jq, and Lefthook. Open AppShot has no runtime package dependency.

## Before opening a pull request

Run the publication gates that do not need macOS privacy permissions:

```bash
mise run check
```

When capture, clipboard, or hotkey behavior changes, also run:

```bash
mise run smoke
mise run install
mise run hotkey-smoke
```

The smoke tests need Accessibility and Screen Recording permission. GitHub-hosted runners cannot grant those permissions, so CI runs the bundle and CLI contract suite instead.

Normal ad hoc builds use a code-hash-bound identity. macOS may require renewed Accessibility and Screen Recording consent after code changes. The repository intentionally has no identifier-only signing mode. `mise run hotkey-smoke` installs the current build before testing it.

## Conventions

- Use English in code, comments, commits, issues, and pull requests.
- Use Conventional Commit titles such as `feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, and `test:`.
- Keep pull requests focused and describe any effect on captured data, clipboard content, storage, permissions, or network behavior.
- Run `mise run format` after changing Swift code.
- Do not commit real captures, Accessibility output, credentials, or other private data.
- Do not add UI-control behavior, telemetry, or network upload without an explicit design decision.

Report security problems privately as described in [SECURITY.md](SECURITY.md).
