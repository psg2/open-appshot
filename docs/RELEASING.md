# Releasing Open AppShot

The repository is prepared for continuous integration. Public release publication is intentionally not connected to GitHub yet, but the local release packager fails closed unless Developer ID and notary credentials are configured.

## One-time repository setup

Before making the repository public:

1. Confirm the checked-in MIT License remains the intended license.
2. Add the GitHub remote and push `main`.
3. Enable branch protection with the `Secrets Scan`, `Format · Lint · Build · Test`, and `Minimum macOS 15` checks required.
4. Enable private vulnerability reporting and Dependabot security alerts.
5. Install Renovate and CodeRabbit if those services should manage dependencies and reviews.
6. Confirm that the legacy bundle identifier remains acceptable or plan a documented TCC permission migration.
7. On every machine used by the POC, run `./Scripts/uninstall-local.sh --reset-permissions` before granting permissions to a Developer ID release.

## Release checks

Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, then run the source and local-development checks:

```bash
make check
make smoke
make install
make hotkey-smoke
```

Inspect the installed app, capture history, clipboard modes, settings, permissions, icon, menu bar behavior, and Command-W handling.

For a public binary, create a notarytool keychain profile and run:

```bash
OPEN_APPSHOT_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
OPEN_APPSHOT_NOTARY_PROFILE="open-appshot" \
make package-release
```

The command clears stale release output before building, then produces a versioned universal notarized ZIP and portable SHA-256 checksum under `build/release`. It moves those files into place only after notarization, stapling, Gatekeeper assessment, and checksum generation succeed.

## Distribution signing

A distributable release needs:

- an Apple Developer Program team;
- a Developer ID Application certificate;
- hardened runtime and an explicit entitlements review;
- `codesign` with the Developer ID identity;
- notarization with `notarytool`;
- stapling and Gatekeeper verification;
- a release archive and checksums.

Add a release workflow only after the signing identity, GitHub secret storage, artifact publication policy, and bundle identifier migration are decided. Never place certificate material or App Store Connect credentials in the repository.
