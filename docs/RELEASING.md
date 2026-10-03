# Releasing Open AppShot

Releases are built by `.github/workflows/release.yml` when a `vX.Y.Z` tag is pushed. The workflow checks that the tag matches `VERSION`, runs `mise run test`, packages a universal ad hoc signed archive with `Scripts/package-release.sh`, and publishes the ZIP and its `.sha256` file with `docs/release-notes.md` as the release notes. Only the release job has `contents: write`.

## Repository setup

1. Require the `Secrets Scan`, `Format · Lint · Build · Test`, `Minimum macOS (macos-15)`, and `Minimum macOS (macos-15-intel)` checks on `main`.
2. Enable private vulnerability reporting and Dependabot security alerts.
3. On every machine that used the POC, run `./Scripts/uninstall-local.sh --reset-permissions` before granting permissions to a release build.

## Release checklist

1. Update `VERSION` and `docs/release-notes.md`. Increase `CFBundleVersion` in `Resources/Info.plist`. `Scripts/build.sh` sets `CFBundleShortVersionString` from `VERSION`.
2. Run the local gates, including the permission-dependent smoke tests that CI can't run:

   ```bash
   mise run check
   mise run smoke
   mise run install
   mise run hotkey-smoke
   ```

3. Inspect the installed app, capture history, clipboard modes, settings, permissions, icon, menu bar behavior, and Command-W handling.
4. Merge the version change, then tag the merge commit and push the tag:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

To rerun a failed release for an existing tag, start the Release workflow manually with that tag.

## Signing

Ad hoc releases are not notarized. Users approve the first launch under **Privacy & Security > Open Anyway**. macOS ties Accessibility and Screen Recording grants to the exact ad hoc binary, so users grant both again after every update.

A Developer ID release keeps permissions across updates and opens without the Gatekeeper exception. It needs an Apple Developer Program team, a Developer ID Application certificate, and a notarytool keychain profile. Build it locally with:

```bash
OPEN_APPSHOT_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
OPEN_APPSHOT_NOTARY_PROFILE="open-appshot" \
mise run package-release
```

That path enables the hardened runtime, then notarizes, staples, and runs a Gatekeeper assessment before it writes the archive. Moving the release workflow to Developer ID requires storing the certificate and notary credentials as GitHub secrets. Never commit certificate material or App Store Connect credentials.
