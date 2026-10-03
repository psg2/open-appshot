import Foundation
import OpenAppShotCore
import Testing

struct CaptureStorageTests {
    private let fileManager = FileManager.default

    private func temporaryRoot() throws -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent("open-appshot-tests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeMarker(in directory: URL, createdAt: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"createdAt":"\#(createdAt)"}"#.utf8)
            .write(to: directory.appendingPathComponent(CaptureStorage.markerFilename))
    }

    @Test func keepsStagingDirectoriesOfCapturesInProgress() throws {
        let root = try temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let staging = try CaptureStorage.createStagingDirectory(at: root, capturedAt: Date())

        let removed = try CaptureStorage.removeExpiredCaptures(at: root, retentionDays: 1)

        #expect(removed.isEmpty)
        #expect(fileManager.fileExists(atPath: staging.path))
    }

    @Test func keepsManagedCapturesForeverWhenRetentionIsZero() throws {
        let root = try temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let capture = root.appendingPathComponent("2020-01-01T00-00-00Z-11111111-1111-4111-8111-111111111111")
        try writeMarker(in: capture, createdAt: "2020-01-01T00:00:00Z")

        let removed = try CaptureStorage.removeExpiredCaptures(at: root, retentionDays: 0)

        #expect(removed.isEmpty)
        #expect(fileManager.fileExists(atPath: capture.path))
    }

    @Test func keepsLegacyLookalikeWhoseMetadataNamesAnotherCapture() throws {
        let root = try temporaryRoot()
        defer { try? fileManager.removeItem(at: root) }
        let name = "2020-01-01T00-00-00Z-22222222-2222-4222-8222-222222222222"
        let directory = root.appendingPathComponent(name)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("# AppShot context\n".utf8).write(to: directory.appendingPathComponent("context.md"))
        try Data().write(to: directory.appendingPathComponent("screenshot.png"))
        try Data().write(to: directory.appendingPathComponent("accessibility.json"))
        try Data(#"{"id":"someone-else","capturedAt":"2020-01-01T00:00:00Z"}"#.utf8)
            .write(to: directory.appendingPathComponent("metadata.json"))

        let removed = try CaptureStorage.removeExpiredCaptures(at: root, retentionDays: 1)

        #expect(removed.isEmpty)
        #expect(!CaptureStorage.hasVerifiedLegacyLayout(directory))
    }
}
