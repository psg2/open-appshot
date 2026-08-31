# Open AppShot

Open AppShot captures the visible state and readable UI structure of one macOS window so a person can pass that context to a local or remote agent.

## Language

**Capture**:
A stored observation of one application window at one point in time. It contains window pixels and a redacted Accessibility tree.
_Avoid_: Screenshot, recording

**Clipboard mode**:
A named, mutually exclusive set of representations copied from a capture. A mode may include pixels, Accessibility content, or local file references.
_Avoid_: Detail level, clipboard preset

**Full Accessibility context**:
Readable text for every Accessibility element collected in a capture, together with its redacted structured representation.
_Avoid_: OCR, transcript

**File reference**:
An absolute local path to a stored part of a capture. It points to content without placing that content itself on the clipboard.
_Avoid_: Attachment, upload
