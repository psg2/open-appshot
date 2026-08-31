# Peekaboo dependency assessment

## Executive conclusion

Open AppShot can replace its external Peekaboo executable with a small native
observation engine. The underlying macOS APIs are public and a 168-line probe
successfully captured both an exact window image and its Accessibility tree.

The replacement is viable, but production parity is not a trivial copy-and-paste
exercise. Peekaboo contains substantial hardening for ambiguous window identity,
multiple displays and scales, slow or malformed Accessibility trees, sparse web
content, deadlines, partial results, and capture fallbacks. Open AppShot should
implement only its observation contract, initially retaining Peekaboo as an
optional fallback while the native path is exercised against representative apps.

Recommended direction: build a native `ObservationEngine` with public macOS APIs,
validate it in parallel with the current engine, and then remove the Homebrew
runtime requirement. Do not embed the full `PeekabooAutomationKit` product and do
not copy Peekaboo's private ScreenCaptureKit fallback.

## Scope of this assessment

The source review used the official [openclaw/Peekaboo repository](https://github.com/openclaw/Peekaboo)
at commit [`8d5e638`](https://github.com/openclaw/Peekaboo/tree/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec),
checked out on 2026-08-31. The assessment covers only the read-only behavior needed
by Open AppShot:

- discover the target application's preferred window;
- capture that exact window as pixels;
- collect a bounded, redacted Accessibility representation;
- return useful partial results when either side fails.

It does not cover clicks, typing, scrolling, OCR, agent behavior, remote control,
or Peekaboo's CLI and daemon features.

## Current Open AppShot contract

`CaptureEngine` currently starts three kinds of Peekaboo CLI operation:

1. `window list` selects a window and obtains its WindowServer ID, title, and bounds;
2. `see` attempts an exact-window screenshot and AX observation together;
3. separate pixel-only and tree-only `see` calls recover partial output when the
   combined operation fails.

Open AppShot itself already owns the rest of the product: secure-value redaction,
capture bundles, thumbnails, metadata, history, retention, UI, and clipboard
representations. A replacement therefore needs an observation engine, not a
general computer-use framework.

## What Peekaboo actually does

The happy path is based on the same public frameworks available to Open AppShot:

- [`SCShareableContent`](https://developer.apple.com/documentation/screencapturekit/scshareablecontent)
  enumerates shareable applications, displays, and windows;
- [`SCContentFilter(desktopIndependentWindow:)`](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:))
  isolates one window;
- [`SCScreenshotManager.captureImage`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(contentfilter:configuration:))
  captures its pixels;
- `AXUIElementCreateApplication` plus
  [`AXUIElementCopyAttributeValue`](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue)
  reads the target application's Accessibility tree.

The complexity is in the surrounding reliability work. Relevant upstream areas
include:

- [window enumeration and enrichment](https://github.com/openclaw/Peekaboo/blob/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/System/ApplicationService%2BWindowListing.swift),
  combining ScreenCaptureKit, Core Graphics, process identity, AX state, layers,
  alpha, visibility, titles, bounds, and stable window IDs;
- [window identity utilities](https://github.com/openclaw/Peekaboo/blob/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Utilities/WindowIdentityUtilities.swift),
  which handle duplicate and changing windows instead of relying only on a title;
- [exact-window ScreenCaptureKit capture](https://github.com/openclaw/Peekaboo/blob/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/Capture/ScreenCaptureKitOperator%2BWindow.swift)
  and [capture planning](https://github.com/openclaw/Peekaboo/blob/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/Capture/ScreenCapturePlanner.swift),
  including display topology, point-to-pixel scaling, shadows, expected dimensions,
  retries, and bounded capture operations;
- [AX traversal](https://github.com/openclaw/Peekaboo/blob/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/DetachedAXObservationWorker.swift),
  which applies short per-call messaging timeouts, a cooperative overall deadline,
  depth/element/child budgets, and explicit incomplete/truncated metadata;
- [AX descriptor reads](https://github.com/openclaw/Peekaboo/blob/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/AXDescriptorReader.swift)
  and [tree collection](https://github.com/openclaw/Peekaboo/blob/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/AXTreeCollector.swift),
  which read several child collections and tolerate partial attribute failures;
- a focused [`AXWebArea` fallback](https://github.com/openclaw/Peekaboo/blob/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/UI/WebFocusFallback.swift)
  for sparse Chromium and Electron trees.

At the reviewed revision, `PeekabooAutomationKit` alone contains 294 Swift source
files and about 81,000 lines, plus 152 Swift test files. Seven directly relevant
window/capture/AX files total 3,098 lines. Its Swift package also depends on
[`AXorcist`](https://github.com/openclaw/AXorcist) and
[`swift-algorithms`](https://github.com/apple/swift-algorithms). Linking the full
library would remove the separately installed binary but would not produce a small,
independent app.

The upstream repository also contains a
[private ScreenCaptureKit lookup fallback](https://github.com/openclaw/Peekaboo/blob/8d5e638e6ac9e93fae7d8dcb2ac0a0f01f3d49ec/Core/PeekabooAutomationKit/Sources/PeekabooAutomationKit/Services/Capture/LegacyScreenCaptureOperator%2BPrivateScreenCaptureKit.swift).
That behavior is not appropriate for a distributable Open AppShot build. The native
engine should remain on documented public APIs and report an unsupported window as
a partial/failed observation.

## Native proof of concept

A throwaway Swift probe was compiled with warnings treated as errors using only:

- AppKit;
- ApplicationServices;
- ScreenCaptureKit;
- ImageIO and UniformTypeIdentifiers for PNG output.

Against Open AppShot's deterministic fixture, it:

- selected the fixture's layer-zero active window by PID;
- captured the exact window with its shadow at 1040 x 624 pixels;
- matched the AX window by focused state/title;
- serialized 8 AX nodes with role, subrole, title, value, description, help,
  enabled/focused state, bounds, and children;
- bounded traversal to depth 20 and 1,500 nodes;
- redacted secure-role values.

This proves the API path and permission model. It does not prove reliable behavior
for multiple untitled windows, minimized/off-Space windows, Electron/Chromium,
unresponsive AX providers, multiple displays, or changing display scale.

## Options

| Option | External install | Dependency surface | Reliability work | Assessment |
| --- | --- | --- | --- | --- |
| Keep the Peekaboo CLI | Required | Executable plus CLI JSON contract | Already upstream | Reliable current baseline, but poor install UX |
| Link `PeekabooAutomationKit` | Not required | About 81k source lines plus dependencies | Mostly upstream | Removes Homebrew only; too broad for this app |
| Copy selected Peekaboo files | Not required | Entangled types and transitive helpers | High and hard to maintain | Not recommended |
| Implement a scoped native engine | Not required | Estimated 800-1,500 app-owned lines plus tests | Focused on observation only | Recommended |

The line and schedule estimates are engineering estimates, not measurements of a
completed implementation. A first usable path is likely 2-4 focused development
days. A hardened replacement across the app matrix is more plausibly 1-2 weeks.

## Required production hardening

A native implementation should not ship as the only engine until it has:

1. **Stable window resolution.** Correlate `SCWindow`, `CGWindowID`, PID, title,
   bounds, layer, active state, and AX window identity. Define deterministic
   behavior for multiple windows and empty titles.
2. **Correct pixel geometry.** Resolve point-to-pixel scale per display, preserve
   the chosen shadow policy, and validate output dimensions.
3. **Bounded AX reads.** Run AX traversal away from the main actor, set a short
   `AXUIElementSetMessagingTimeout`, enforce overall time/depth/node/child limits,
   and mark partial results instead of hanging capture.
4. **Useful AX coverage.** Read normal children plus navigation-order, visible,
   row, and web-area child collections when available. Deduplicate nodes.
5. **Privacy preservation.** Keep secure-field redaction in the observation model
   before any JSON, Markdown, history, or clipboard output is created.
6. **Independent failure domains.** Pixel and AX failures must remain separable so
   one useful representation can still be stored and copied.
7. **Representative fixtures.** Exercise native AppKit/SwiftUI, Finder, Slack or
   another Electron app, a Chromium browser, multiple windows, multiple displays,
   permission denial, AX timeout, and partial-tree truncation.

## Recommended migration

1. Introduce an `ObservationEngine` protocol whose result uses Open AppShot's own
   window and AX models rather than Peekaboo JSON dictionaries.
2. Move the current process calls behind `PeekabooObservationEngine` without
   changing behavior.
3. Add `NativeObservationEngine` using public ScreenCaptureKit and AX APIs.
4. During development, optionally run both engines for explicit test captures and
   compare selected window, pixel dimensions, element counts, truncation state,
   and redaction. Do not silently double-capture normal user content.
5. Make native the default after the fixture matrix passes, leaving Peekaboo as an
   opt-in diagnostic fallback for one release.
6. Remove Peekaboo lookup, installation instructions, and the fallback after the
   native engine has field evidence across the target app set.

This staged approach removes the user-facing dependency without pretending that
the 168-line happy-path probe already contains Peekaboo's reliability behavior.
