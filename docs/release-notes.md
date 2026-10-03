Open AppShot captures the last active macOS window as pixels and Accessibility context, keeps a local history, and copies both to the clipboard for chat and agent apps.

- Global capture shortcut. The default is Left Option + Right Option, and any shortcut with two modifiers works.
- Four clipboard modes: image with full Accessibility text, image with file references, image only, and Accessibility only.
- Secure and password fields are redacted from the Accessibility output.
- Captures stay on this Mac with private file permissions. Retention runs from 1 day to forever.
- Universal Apple Silicon and Intel app for macOS 15 or later.

Releases are ad hoc signed. They aren't Developer ID signed or notarized. Verify the archive with its `.sha256` file and follow the [first-open steps](https://github.com/psg2/open-appshot#install-a-release). macOS asks for Accessibility and Screen Recording again after each update.

The app captures only. It doesn't click, type, upload, or send telemetry.
