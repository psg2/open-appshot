# Releasing Open AppShot

The repository is prepared for continuous integration, but public binary releases are intentionally not automated yet. Current builds use an ad hoc signature, which is suitable for local development but not public distribution.

## One-time repository setup

Before making the repository public:

1. Choose an open-source license and add it as `LICENSE`.
2. Add the GitHub remote and push `main`.
3. Enable branch protection with the `Secrets Scan` and `Format · Lint · Build · Test` checks required.
4. Enable private vulnerability reporting and Dependabot security alerts.
5. Install Renovate and CodeRabbit if those services should manage dependencies and reviews.
6. Confirm that the legacy bundle identifier remains acceptable or plan a documented TCC permission migration.

## Release checks

Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, then run:

```bash
make check
make smoke
make install
make hotkey-smoke
```

Inspect the installed app, capture history, clipboard modes, settings, permissions, icon, menu bar behavior, and Command-W handling.

## Distribution signing

A distributable release needs:

- an Apple Developer Program team;
- a Developer ID Application certificate;
- hardened runtime and an explicit entitlements review;
- `codesign` with the Developer ID identity;
- notarization with `notarytool`;
- stapling and Gatekeeper verification;
- a release archive and checksums.

Add a release workflow only after the signing identity, secret storage, license, artifact format, and bundle identifier migration are decided. Never place certificate material or App Store Connect credentials in the repository.
