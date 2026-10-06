import AppKit
import ApplicationServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum AppShotError: LocalizedError {
    case noTargetApplication
    case commandFailed(String)
    case missingScreenshot
    case invalidArguments(String)

    public var errorDescription: String? {
        switch self {
        case .noTargetApplication:
            return "No frontmost application is available."
        case .commandFailed(let message):
            return message
        case .missingScreenshot:
            return "The capture engine completed without producing a screenshot."
        case .invalidArguments(let message):
            return message
        }
    }
}

public struct Snapshot {
    public let id: String
    public let capturedAt: Date
    public let directoryURL: URL
    public let screenshotURL: URL
    public let accessibilityURL: URL
    public let contextURL: URL
    public let contextText: String
    public let accessibilityJSON: Data
    public let appName: String
    public let windowTitle: String
    public let elementCount: Int
    public let captureStrategy: String
}

public final class CaptureEngine {
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let retentionRoots: [URL]
    private let retentionDays: Int
    private let observationEngine: NativeObservationEngine

    public init(
        baseDirectory: URL = CapturePreferences.captureRootURL,
        retentionRoots: [URL] = CapturePreferences.knownCaptureRootURLs,
        retentionDays: Int = CapturePreferences.retentionDays,
        observationEngine: NativeObservationEngine = NativeObservationEngine()
    ) {
        self.baseDirectory = baseDirectory
        var seen: Set<String> = []
        self.retentionRoots = ([baseDirectory] + retentionRoots).filter {
            seen.insert($0.standardizedFileURL.path).inserted
        }
        self.retentionDays = retentionDays
        self.observationEngine = observationEngine
    }

    public func capture(application: NSRunningApplication) throws -> Snapshot {
        try CaptureStorage.prepareRoot(baseDirectory, fileManager: fileManager)
        try CaptureStorage.removeExpiredCaptures(
            at: baseDirectory,
            retentionDays: retentionDays,
            fileManager: fileManager
        )
        for root in retentionRoots where root.standardizedFileURL != baseDirectory.standardizedFileURL {
            _ = try? CaptureStorage.removeExpiredCaptures(
                at: root,
                retentionDays: retentionDays,
                fileManager: fileManager
            )
        }

        let capturedAt = Date()
        let id = snapshotDirectoryName(for: capturedAt)
        let finalDirectory = baseDirectory.appendingPathComponent(id, isDirectory: true)
        let captureDirectory = try CaptureStorage.createStagingDirectory(
            at: baseDirectory,
            capturedAt: capturedAt,
            fileManager: fileManager
        )
        var committed = false
        defer {
            if !committed {
                try? fileManager.removeItem(at: captureDirectory)
            }
        }

        let pid = application.processIdentifier
        let appName = application.localizedName ?? application.bundleIdentifier ?? "PID \(pid)"
        let observation = try observationEngine.observe(application: application, captureDirectory: captureDirectory)
        let screenshotURL = captureDirectory.appendingPathComponent("screenshot.png")
        let accessibilityURL = captureDirectory.appendingPathComponent("accessibility.json")
        let accessibilityJSON = try observation.accessibilityJSON()
        try accessibilityJSON.write(to: accessibilityURL, options: .atomic)

        guard fileManager.fileExists(atPath: screenshotURL.path) else {
            throw AppShotError.missingScreenshot
        }
        let thumbnailURL = captureDirectory.appendingPathComponent("thumbnail.png")
        try writeThumbnail(from: screenshotURL, to: thumbnailURL)

        let contextText = buildContext(
            appName: appName,
            bundleIdentifier: application.bundleIdentifier,
            pid: pid,
            capturedAt: capturedAt,
            observation: observation,
            captureDirectory: finalDirectory,
            captureStrategy: observation.captureStrategy
        )
        let contextURL = captureDirectory.appendingPathComponent("context.md")
        try contextText.write(to: contextURL, atomically: true, encoding: .utf8)

        let metadata = CaptureMetadata(
            id: id,
            capturedAt: capturedAt,
            appName: appName,
            bundleIdentifier: application.bundleIdentifier,
            windowTitle: observation.window.title,
            elementCount: observation.elements.count,
            captureStrategy: observation.captureStrategy
        )
        let metadataURL = captureDirectory.appendingPathComponent("metadata.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)

        try setPrivatePermissions(
            on: [screenshotURL, thumbnailURL, accessibilityURL, contextURL, metadataURL] + observation.diagnosticURLs)

        try fileManager.moveItem(at: captureDirectory, to: finalDirectory)
        committed = true

        return Snapshot(
            id: id,
            capturedAt: capturedAt,
            directoryURL: finalDirectory,
            screenshotURL: finalDirectory.appendingPathComponent("screenshot.png"),
            accessibilityURL: finalDirectory.appendingPathComponent("accessibility.json"),
            contextURL: finalDirectory.appendingPathComponent("context.md"),
            contextText: contextText,
            accessibilityJSON: accessibilityJSON,
            appName: appName,
            windowTitle: observation.window.title,
            elementCount: observation.elements.count,
            captureStrategy: observation.captureStrategy
        )
    }

    private func snapshotDirectoryName(for capturedAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: capturedAt).replacingOccurrences(of: ":", with: "-") + "-"
            + UUID().uuidString.lowercased()
    }

    private func buildContext(
        appName: String,
        bundleIdentifier: String?,
        pid: pid_t,
        capturedAt: Date,
        observation: ObservationResult,
        captureDirectory: URL,
        captureStrategy: String
    ) -> String {
        var lines = [
            "# AppShot context",
            "",
            "Captured: \(ISO8601DateFormatter().string(from: capturedAt))",
            "Application: \(appName)",
            "Bundle ID: \(bundleIdentifier ?? "unknown")",
            "PID: \(pid)",
            "Window: \(observation.window.title)",
            "Window ID: \(observation.window.id)",
            "Observation engine: Native macOS",
            "Capture strategy: \(captureStrategy)",
            "Accessibility elements: \(observation.elements.count)",
            "Capture directory: \(captureDirectory.path)",
            "Screenshot: \(captureDirectory.appendingPathComponent("screenshot.png").path)",
            "",
            "The clipboard carries this text and the screenshot PNG together.",
            "Some apps paste only the text. If no image is attached, open the Screenshot file above.",
            "",
            "## Accessibility summary",
            "",
        ]

        for element in observation.elements {
            lines.append(elementLine(element))
        }

        if observation.truncation.isIncomplete {
            lines.append("")
            lines.append("Accessibility truncation metadata: \(compactTruncation(observation.truncation))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func elementLine(_ element: ObservedElement) -> String {
        let role = cleanText(element.role, maximum: 80)
        if element.isSecure {
            return "- \(role): [secure value redacted]"
        }

        var descriptions: [String] = []
        for value in [element.label, element.title, element.value, element.elementDescription, element.help].compactMap({ $0 }) {
            let cleaned = cleanText(value, maximum: 320)
            guard !cleaned.isEmpty, !descriptions.contains(cleaned) else { continue }
            descriptions.append(cleaned)
        }
        let text = descriptions.isEmpty ? "unnamed" : descriptions.joined(separator: " | ")

        var suffix: [String] = []
        if let bounds = element.bounds {
            suffix.append("bounds=\(Int(bounds.x)),\(Int(bounds.y)),\(Int(bounds.width)),\(Int(bounds.height))")
        }
        if element.isActionable {
            suffix.append("actionable")
        }
        if element.isEnabled == false {
            suffix.append("disabled")
        }
        let metadata = suffix.isEmpty ? "" : " [\(suffix.joined(separator: ", "))]"
        return "- \(role): \(text)\(metadata)"
    }

    private func cleanText(_ value: String, maximum: Int) -> String {
        let oneLine =
            value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if oneLine.count <= maximum { return oneLine }
        return String(oneLine.prefix(maximum)) + "…"
    }

    private func compactTruncation(_ truncation: ObservationTruncation) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(truncation),
            let text = String(data: data, encoding: .utf8)
        else { return "unavailable" }
        return text
    }

    private func writeThumbnail(from sourceURL: URL, to destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw AppShotError.missingScreenshot
        }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
            ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
            let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw AppShotError.missingScreenshot
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AppShotError.commandFailed("Could not write the capture thumbnail.")
        }
    }

    private func setPrivatePermissions(on urls: [URL]) throws {
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
