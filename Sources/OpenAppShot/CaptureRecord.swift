import AppKit
import Foundation

struct CaptureMetadata: Codable, Hashable {
    let id: String
    let capturedAt: Date
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String
    let elementCount: Int
    let captureStrategy: String
}

struct CaptureRecord: Identifiable, Hashable {
    let metadata: CaptureMetadata
    let directoryURL: URL
    let isLegacy: Bool
    let canDelete: Bool

    var id: String { metadata.id }
    var screenshotURL: URL { directoryURL.appendingPathComponent("screenshot.png") }
    var thumbnailURL: URL? {
        let url = directoryURL.appendingPathComponent("thumbnail.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var accessibilityURL: URL { directoryURL.appendingPathComponent("accessibility.json") }
    var contextURL: URL { directoryURL.appendingPathComponent("context.md") }
    var hasVerifiedOwnership: Bool {
        CaptureStorage.hasOwnershipMarker(directoryURL)
            || CaptureStorage.hasVerifiedLegacyLayout(directoryURL)
    }

    func snapshot() throws -> Snapshot {
        Snapshot(
            id: metadata.id,
            capturedAt: metadata.capturedAt,
            directoryURL: directoryURL,
            screenshotURL: screenshotURL,
            accessibilityURL: accessibilityURL,
            contextURL: contextURL,
            contextText: try String(contentsOf: contextURL, encoding: .utf8),
            accessibilityJSON: try Data(contentsOf: accessibilityURL),
            appName: metadata.appName,
            windowTitle: metadata.windowTitle,
            elementCount: metadata.elementCount,
            captureStrategy: metadata.captureStrategy
        )
    }
}
