import Foundation

enum CaptureStorage {
    static let markerFilename = ".open-appshot-capture"

    private struct Marker: Codable {
        let createdAt: Date
    }

    private struct StoredMetadata: Codable {
        let id: String
        let capturedAt: Date
    }

    static func isCaptureDirectoryName(_ name: String) -> Bool {
        let pattern =
            #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    static func hasOwnershipMarker(_ directory: URL) -> Bool {
        guard isCaptureDirectoryName(directory.lastPathComponent) else { return false }
        let markerURL = directory.appendingPathComponent(markerFilename)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: markerURL) else { return false }
        return (try? decoder.decode(Marker.self, from: data)) != nil
    }

    static func hasStagingOwnershipMarker(_ directory: URL) -> Bool {
        let name = directory.lastPathComponent
        guard name.hasPrefix(".staging-"), UUID(uuidString: String(name.dropFirst(".staging-".count))) != nil else {
            return false
        }
        return markerDate(in: directory) != nil
    }

    static func hasVerifiedLegacyLayout(_ directory: URL, fileManager: FileManager = .default) -> Bool {
        guard isCaptureDirectoryName(directory.lastPathComponent),
            let context = try? String(
                contentsOf: directory.appendingPathComponent("context.md"),
                encoding: .utf8
            ),
            context.hasPrefix("# AppShot context\n"),
            fileManager.fileExists(atPath: directory.appendingPathComponent("screenshot.png").path),
            fileManager.fileExists(atPath: directory.appendingPathComponent("accessibility.json").path)
        else { return false }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadataURL = directory.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataURL),
            let metadata = try? decoder.decode(StoredMetadata.self, from: data)
        else { return false }
        return metadata.id == directory.lastPathComponent
    }

    static func prepareRoot(_ root: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    static func createStagingDirectory(
        at root: URL,
        capturedAt: Date,
        fileManager: FileManager = .default
    ) throws -> URL {
        try prepareRoot(root, fileManager: fileManager)
        let directory = root.appendingPathComponent(".staging-\(UUID().uuidString.lowercased())", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let markerURL = directory.appendingPathComponent(markerFilename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Marker(createdAt: capturedAt)).write(to: markerURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: markerURL.path)
        return directory
    }

    @discardableResult
    static func removeExpiredCaptures(
        at root: URL,
        retentionDays: Int,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        let expiration =
            retentionDays > 0
            ? now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
            : nil
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        var removed: [URL] = []
        for child in children {
            let managedDate = managedCaptureDate(for: child, under: root, fileManager: fileManager)
            let abandonedStagingDate = stagingDate(for: child, under: root, fileManager: fileManager)
            let shouldRemoveManagedCapture = expiration.flatMap { cutoff in managedDate.map { $0 < cutoff } } ?? false
            let shouldRemoveAbandonedStaging = abandonedStagingDate.map { $0 < now.addingTimeInterval(-60 * 60) } ?? false
            guard shouldRemoveManagedCapture || shouldRemoveAbandonedStaging else { continue }
            if (try? fileManager.removeItem(at: child)) != nil {
                removed.append(child)
            }
        }
        return removed
    }

    @discardableResult
    static func purgeOwnedCaptures(at root: URL, fileManager: FileManager = .default) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        var removed: [URL] = []
        for child in children {
            let ownsCapture = managedCaptureDate(for: child, under: root, fileManager: fileManager) != nil
            let ownsStaging = stagingDate(for: child, under: root, fileManager: fileManager) != nil
            guard ownsCapture || ownsStaging else { continue }
            try fileManager.removeItem(at: child)
            removed.append(child)
        }
        return removed
    }

    private static func stagingDate(for directory: URL, under root: URL, fileManager: FileManager) -> Date? {
        guard directory.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
            let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            values.isDirectory == true,
            values.isSymbolicLink != true,
            hasStagingOwnershipMarker(directory)
        else { return nil }
        return markerDate(in: directory)
    }

    private static func markerDate(in directory: URL) -> Date? {
        let markerURL = directory.appendingPathComponent(markerFilename)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: markerURL), let marker = try? decoder.decode(Marker.self, from: data) else {
            return nil
        }
        return marker.createdAt
    }

    private static func managedCaptureDate(for directory: URL, under root: URL, fileManager: FileManager) -> Date? {
        guard directory.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
            let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            values.isDirectory == true,
            values.isSymbolicLink != true
        else { return nil }

        if isCaptureDirectoryName(directory.lastPathComponent), let date = markerDate(in: directory) {
            return date
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadataURL = directory.appendingPathComponent("metadata.json")
        guard hasVerifiedLegacyLayout(directory, fileManager: fileManager),
            let data = try? Data(contentsOf: metadataURL),
            let metadata = try? decoder.decode(StoredMetadata.self, from: data),
            metadata.id == directory.lastPathComponent
        else { return nil }
        return metadata.capturedAt
    }
}
