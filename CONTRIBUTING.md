# Contributing

Thanks for helping improve Open AppShot. The project is intentionally capture-only: it observes a selected window but does not click, type, scroll, or invoke UI actions.

## Development setup

You need macOS 15 or later and full Xcode. Install the repository tools and Git hooks:

```bash
make setup
make hooks
```

`make setup` installs Peekaboo, Gitleaks, ShellCheck, actionlint, jq, and Lefthook from the checked-in `Brewfile`.

## Before opening a pull request

Run the publication gates that do not need macOS privacy permissions:

```bash
make check
```

When capture, clipboard, or hotkey behavior changes, also run:

```bash
make smoke
make install
make hotkey-smoke
```

The smoke tests need Accessibility and Screen Recording permission. GitHub-hosted runners cannot grant those permissions, so CI runs the bundle and CLI contract suite instead.

## Conventions

- Use English in code, comments, commits, issues, and pull requests.
- Use Conventional Commit titles such as `feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, and `test:`.
- Keep pull requests focused and describe any effect on captured data, clipboard content, storage, permissions, or network behavior.
- Run `make format` after changing Swift code.
- Do not commit real captures, Accessibility output, credentials, or other private data.
- Do not add UI-control behavior, telemetry, or network upload without an explicit design decision.

Report security problems privately as described in [SECURITY.md](SECURITY.md).
