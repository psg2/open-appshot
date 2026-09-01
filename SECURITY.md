# Security policy

## Supported versions

Until tagged releases exist, only the current `main` branch receives security fixes.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub Security Advisories: open the repository's **Security** tab and choose **Report a vulnerability**. Do not open a public issue or pull request for security problems.

If private reporting is not enabled, contact the maintainer through the links on the [psg2 GitHub profile](https://github.com/psg2). Repository maintainers should enable **Settings > Code security > Private vulnerability reporting** before publication.

Include the affected version, macOS version, reproduction steps, and impact. Remove private screenshot and Accessibility content from the report unless it is essential to reproduce the issue.

## Scope notes

Open AppShot handles sensitive local data:

- screenshots can contain anything visible in the captured window;
- Accessibility output can contain readable labels, values, and structure;
- clipboard output can be read by the receiving application;
- Accessibility and Screen Recording are powerful macOS permissions.

Reports about permission bypasses, capture of the wrong window, insecure file permissions, unsafe retention, insufficient redaction, clipboard disclosure, or unexpected network access are in scope. Vulnerabilities in macOS or a captured third-party application should also be reported to their respective maintainers.

Machines that granted permissions to an early identifier-only development build should run `./Scripts/uninstall-local.sh --reset-permissions` before using a signed public release. This removes the weak historical TCC grants and requires fresh consent for the Developer ID build.
