import Foundation

enum CaptureHistory {
    static func load() -> [CaptureRecord] {
        var roots = CapturePreferences.knownCaptureRootURLs.map { ($0, false) }
        let legacy = CapturePreferences.legacyCaptureRootURL
        if !roots.contains(where: { $0.0.standardizedFileURL == legacy.standardizedFileURL }) {
            roots.append((legacy, true))
        }
        if let legacyCustom = CapturePreferences.legacyCustomCaptureRootURL,
            !roots.contains(where: { $0.0.standardizedFileURL == legacyCustom.standardizedFileURL })
        {
            roots.append((legacyCustom, true))
        }

        return
            roots
            .flatMap { load(root: $0.0, isLegacy: $0.1) }
            .sorted { $0.metadata.capturedAt > $1.metadata.capturedAt }
    }

    private static func load(root: URL, isLegacy: Bool) -> [CaptureRecord] {
        guard
            let directories = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        return directories.compactMap { directory in
            guard
                let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true,
                values.isSymbolicLink != true,
                FileManager.default.fileExists(atPath: directory.appendingPathComponent("screenshot.png").path),
                FileManager.default.fileExists(atPath: directory.appendingPathComponent("context.md").path)
            else { return nil }

            let hasMarker = CaptureStorage.hasOwnershipMarker(directory)
            let hasVerifiedLegacyLayout = CaptureStorage.hasVerifiedLegacyLayout(directory)

            let metadataURL = directory.appendingPathComponent("metadata.json")
            if hasMarker || hasVerifiedLegacyLayout, let data = try? Data(contentsOf: metadataURL) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let metadata = try? decoder.decode(CaptureMetadata.self, from: data),
                    metadata.id == directory.lastPathComponent
                {
                    return CaptureRecord(
                        metadata: metadata,
                        directoryURL: directory,
                        isLegacy: isLegacy || !hasMarker,
                        canDelete: true
                    )
                }
            }

            guard isLegacy, let metadata = legacyMetadata(directory: directory) else { return nil }
            return CaptureRecord(metadata: metadata, directoryURL: directory, isLegacy: true, canDelete: false)
        }
    }

    private static func legacyMetadata(directory: URL) -> CaptureMetadata? {
        let contextURL = directory.appendingPathComponent("context.md")
        guard CaptureStorage.isCaptureDirectoryName(directory.lastPathComponent),
            let context = try? String(contentsOf: contextURL, encoding: .utf8),
            context.hasPrefix("# AppShot context\n"),
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("accessibility.json").path)
        else { return nil }

        let capturedAt =
            value(after: "Captured:", in: context)
            .flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? (try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate)
            ?? .distantPast

        return CaptureMetadata(
            id: directory.lastPathComponent,
            capturedAt: capturedAt,
            appName: value(after: "Application:", in: context) ?? "Unknown app",
            bundleIdentifier: value(after: "Bundle ID:", in: context),
            windowTitle: value(after: "Window:", in: context) ?? "Untitled window",
            elementCount: Int(value(after: "Accessibility elements:", in: context) ?? "0") ?? 0,
            captureStrategy: value(after: "Capture strategy:", in: context) ?? "Legacy capture"
        )
    }

    private static func value(after prefix: String, in text: String) -> String? {
        text.split(separator: "\n")
            .map(String.init)
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
    }
}
