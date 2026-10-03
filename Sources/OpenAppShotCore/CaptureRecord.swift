import AppKit
import Foundation

public struct CaptureMetadata: Codable, Hashable {
    public let id: String
    public let capturedAt: Date
    public let appName: String
    public let bundleIdentifier: String?
    public let windowTitle: String
    public let elementCount: Int
    public let captureStrategy: String
}

public struct CaptureRecord: Identifiable, Hashable {
    public let metadata: CaptureMetadata
    public let directoryURL: URL
    public let isLegacy: Bool
    public let canDelete: Bool

    public var id: String { metadata.id }
    public var screenshotURL: URL { directoryURL.appendingPathComponent("screenshot.png") }
    public var thumbnailURL: URL? {
        let url = directoryURL.appendingPathComponent("thumbnail.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    public var accessibilityURL: URL { directoryURL.appendingPathComponent("accessibility.json") }
    public var contextURL: URL { directoryURL.appendingPathComponent("context.md") }
    public var hasVerifiedOwnership: Bool {
        CaptureStorage.hasOwnershipMarker(directoryURL)
            || CaptureStorage.hasVerifiedLegacyLayout(directoryURL)
    }

    public func snapshot() throws -> Snapshot {
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
