import AppKit
import ApplicationServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

let customContextType = NSPasteboard.PasteboardType("com.psg2.appshot-context-json")

enum ClipboardWriter {
    static func copy(_ snapshot: Snapshot, mode: ClipboardMode) throws {
        let item = NSPasteboardItem()

        if mode.includesImage {
            let imageData = try Data(contentsOf: snapshot.screenshotURL)
            item.setData(imageData, forType: .png)
        }
        if mode.includesFullContext {
            item.setString(snapshot.contextText, forType: .string)
        }
        if mode.includesFileReferences {
            item.setString(fileReferenceText(snapshot), forType: .string)
        }
        if mode.includesStructuredContext {
            item.setData(snapshot.accessibilityJSON, forType: customContextType)
        }

        write(item)
    }

    static func copyScreenshot(_ snapshot: Snapshot) throws {
        try copy(snapshot, mode: .imageOnly)
    }

    static func copyContext(_ snapshot: Snapshot) throws {
        try copy(snapshot, mode: .accessibilityOnly)
    }

    static func describeClipboard() -> String {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types?.map(\.rawValue).sorted() ?? []
        let pngBytes = pasteboard.data(forType: .png)?.count ?? 0
        let textCharacters = pasteboard.string(forType: .string)?.count ?? 0
        let contextBytes = pasteboard.data(forType: customContextType)?.count ?? 0
        return [
            "types=\(types.joined(separator: ","))",
            "png_bytes=\(pngBytes)",
            "text_characters=\(textCharacters)",
            "context_json_bytes=\(contextBytes)",
        ].joined(separator: "\n")
    }

    static func clipboardText() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    private static func fileReferenceText(_ snapshot: Snapshot) -> String {
        [
            "# Open AppShot capture",
            "",
            "Captured: \(ISO8601DateFormatter().string(from: snapshot.capturedAt))",
            "Application: \(snapshot.appName)",
            "Window: \(snapshot.windowTitle)",
            "Accessibility elements: \(snapshot.elementCount)",
            "Screenshot: \(snapshot.screenshotURL.path)",
            "Accessibility JSON: \(snapshot.accessibilityURL.path)",
            "Readable context: \(snapshot.contextURL.path)",
            "",
            "These files remain local on this Mac.",
        ].joined(separator: "\n") + "\n"
    }

    private static func write(_ item: NSPasteboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
