# Contributing

Open AppShot only observes windows. It doesn't click, type, scroll, or trigger UI actions, and changes that add any of that need a design discussion first.

Keep capture, storage, and clipboard logic in `OpenAppShotCore` and presentation in the `OpenAppShot` app target.

## Setup

You need macOS 15 or later, Xcode 16 or later, and [mise](https://mise.jdx.dev/):

```sh
mise install       # pinned Gitleaks, ShellCheck, actionlint, jq, and Lefthook
mise run hooks     # pre-push hook that runs `mise run check`
```

## Before opening a pull request

```sh
mise run format
mise run check
```

`check` runs lint, unit tests, the contract tests, and Gitleaks. It doesn't need macOS permissions, and CI runs the same gates.

When you change capture, clipboard, or shortcut behavior, also run the permission-dependent tests locally:

```sh
mise run smoke
mise run hotkey-smoke   # installs the current build first
```

Local builds are ad hoc signed, so macOS may ask for Accessibility and Screen Recording again after you rebuild.

## Conventions

- Write code, comments, commits, issues, and pull requests in English.
- Use Conventional Commit messages such as `feat:`, `fix:`, `docs:`, `ci:`, `refactor:`, and `test:`.
- Keep pull requests focused. Say whether the change affects captured data, clipboard content, storage, permissions, or network behavior.
- Test behavior through the `OpenAppShotCore` interface, the built app, or its command-line entry point. Don't assert internal call order or source text.
- Never commit real captures, Accessibility output, credentials, or other private data.

Report security problems privately as described in [SECURITY.md](SECURITY.md).
