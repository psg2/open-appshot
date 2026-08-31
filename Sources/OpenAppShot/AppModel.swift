import AppKit
import ApplicationServices
import Combine
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

    var id: String { metadata.id }
    var screenshotURL: URL { directoryURL.appendingPathComponent("screenshot.png") }
    var thumbnailURL: URL? {
        let url = directoryURL.appendingPathComponent("thumbnail.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var accessibilityURL: URL { directoryURL.appendingPathComponent("accessibility.json") }
    var contextURL: URL { directoryURL.appendingPathComponent("context.md") }

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
            elementCount: metadata.elementCount
        )
    }
}

enum CapturePreferences {
    private static let defaults = UserDefaults.standard
    private static let captureDirectoryKey = "captureDirectoryPath"
    private static let retentionDaysKey = "captureRetentionDays"
    private static let copyAfterCaptureKey = "copyAfterCapture"
    private static let playSoundKey = "playCaptureSound"

    static var defaultCaptureRootURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("Open AppShot", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    static var legacyCaptureRootURL: URL {
        URL(fileURLWithPath: "/tmp/AppShotClipboardPOC", isDirectory: true)
    }

    static var captureRootURL: URL {
        guard let path = defaults.string(forKey: captureDirectoryKey), !path.isEmpty else {
            return defaultCaptureRootURL
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var captureDirectoryPath: String? {
        get { defaults.string(forKey: captureDirectoryKey) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: captureDirectoryKey)
            } else {
                defaults.removeObject(forKey: captureDirectoryKey)
            }
        }
    }

    static var retentionDays: Int {
        get {
            guard defaults.object(forKey: retentionDaysKey) != nil else { return 30 }
            return defaults.integer(forKey: retentionDaysKey)
        }
        set { defaults.set(newValue, forKey: retentionDaysKey) }
    }

    static var copyAfterCapture: Bool {
        get {
            guard defaults.object(forKey: copyAfterCaptureKey) != nil else { return true }
            return defaults.bool(forKey: copyAfterCaptureKey)
        }
        set { defaults.set(newValue, forKey: copyAfterCaptureKey) }
    }

    static var playCaptureSound: Bool {
        get {
            guard defaults.object(forKey: playSoundKey) != nil else { return true }
            return defaults.bool(forKey: playSoundKey)
        }
        set { defaults.set(newValue, forKey: playSoundKey) }
    }
}

enum CaptureHistory {
    static func load() -> [CaptureRecord] {
        var roots = [(CapturePreferences.captureRootURL, false)]
        let defaultRoot = CapturePreferences.defaultCaptureRootURL
        if defaultRoot.standardizedFileURL != CapturePreferences.captureRootURL.standardizedFileURL {
            roots.append((defaultRoot, false))
        }
        let legacy = CapturePreferences.legacyCaptureRootURL
        if !roots.contains(where: { $0.0.standardizedFileURL == legacy.standardizedFileURL }) {
            roots.append((legacy, true))
        }

        return roots
            .flatMap { load(root: $0.0, isLegacy: $0.1) }
            .sorted { $0.metadata.capturedAt > $1.metadata.capturedAt }
    }

    private static func load(root: URL, isLegacy: Bool) -> [CaptureRecord] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent("screenshot.png").path),
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent("context.md").path)
            else { return nil }

            let metadataURL = directory.appendingPathComponent("metadata.json")
            if let data = try? Data(contentsOf: metadataURL) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let metadata = try? decoder.decode(CaptureMetadata.self, from: data) {
                    return CaptureRecord(metadata: metadata, directoryURL: directory, isLegacy: isLegacy)
                }
            }

            guard let metadata = legacyMetadata(directory: directory) else { return nil }
            return CaptureRecord(metadata: metadata, directoryURL: directory, isLegacy: isLegacy)
        }
    }

    private static func legacyMetadata(directory: URL) -> CaptureMetadata? {
        let contextURL = directory.appendingPathComponent("context.md")
        guard let context = try? String(contentsOf: contextURL, encoding: .utf8) else { return nil }

        let capturedAt = value(after: "Captured:", in: context)
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

final class AppModel: ObservableObject {
    @Published private(set) var captures: [CaptureRecord] = []
    @Published var selectedCaptureID: String?
    @Published var previewMode: CapturePreviewMode = .screenshot
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var captureInProgress = false
    @Published private(set) var statusMessage = "Checking permissions…"
    @Published private(set) var storageURL = CapturePreferences.captureRootURL
    @Published var retentionDays = CapturePreferences.retentionDays {
        didSet { CapturePreferences.retentionDays = retentionDays }
    }
    @Published var copyAfterCapture = CapturePreferences.copyAfterCapture {
        didSet { CapturePreferences.copyAfterCapture = copyAfterCapture }
    }
    @Published var playCaptureSound = CapturePreferences.playCaptureSound {
        didSet { CapturePreferences.playCaptureSound = playCaptureSound }
    }

    var captureAction: (() -> Void)?
    var showSettingsAction: (() -> Void)?

    init() {
        reloadHistory()
        refreshPermissions()
    }

    var selectedCapture: CaptureRecord? {
        guard let selectedCaptureID else { return captures.first }
        return captures.first(where: { $0.id == selectedCaptureID }) ?? captures.first
    }

    var isReady: Bool { accessibilityGranted && screenRecordingGranted }

    func reloadHistory(selecting id: String? = nil) {
        captures = CaptureHistory.load()
        if let id, captures.contains(where: { $0.id == id }) {
            selectedCaptureID = id
        } else if let selectedCaptureID, captures.contains(where: { $0.id == selectedCaptureID }) {
            self.selectedCaptureID = selectedCaptureID
        } else {
            selectedCaptureID = captures.first?.id
        }
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        statusMessage = isReady ? "Ready for Left Option + Right Option" : "Two permissions are needed before capture"
    }

    func requestMissingPermissions() {
        if !accessibilityGranted {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        }
        if !screenRecordingGranted {
            _ = CGRequestScreenCaptureAccess()
        }
        refreshPermissions()
    }

    func openAccessibilitySettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        openSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func requestCapture() {
        captureAction?()
    }

    func captureStarted(appName: String) {
        captureInProgress = true
        statusMessage = "Capturing \(appName)…"
    }

    func captureCompleted(_ snapshot: Snapshot) {
        captureInProgress = false
        statusMessage = "Captured \(snapshot.appName) with \(snapshot.elementCount) AX elements"
        reloadHistory(selecting: snapshot.id)
    }

    func captureFailed(_ message: String) {
        captureInProgress = false
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        statusMessage = message
    }

    func copyCombined(_ record: CaptureRecord) {
        performCopy(label: "Screenshot and context copied") {
            try ClipboardWriter.copyCombined(record.snapshot())
        }
    }

    func copyScreenshot(_ record: CaptureRecord) {
        performCopy(label: "Screenshot copied") {
            try ClipboardWriter.copyScreenshot(record.snapshot())
        }
    }

    func copyContext(_ record: CaptureRecord) {
        performCopy(label: "Accessibility context copied") {
            ClipboardWriter.copyContext(try record.snapshot())
        }
    }

    func reveal(_ record: CaptureRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.contextURL])
    }

    func delete(_ record: CaptureRecord) {
        do {
            try FileManager.default.removeItem(at: record.directoryURL)
            statusMessage = "Capture deleted"
            reloadHistory()
        } catch {
            statusMessage = "Could not delete capture: \(error.localizedDescription)"
        }
    }

    func chooseStorageDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose where Open AppShot stores captures"
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = storageURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        CapturePreferences.captureDirectoryPath = url.path
        storageURL = CapturePreferences.captureRootURL
        reloadHistory()
    }

    func useDefaultStorageDirectory() {
        CapturePreferences.captureDirectoryPath = nil
        storageURL = CapturePreferences.captureRootURL
        reloadHistory()
    }

    func revealStorageDirectory() {
        try? FileManager.default.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        NSWorkspace.shared.open(storageURL)
    }

    private func performCopy(label: String, operation: () throws -> Void) {
        do {
            try operation()
            statusMessage = label
            if playCaptureSound { NSSound(named: "Glass")?.play() }
        } catch {
            statusMessage = "Could not copy capture: \(error.localizedDescription)"
            NSSound.beep()
        }
    }

    private func openSettingsURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum CapturePreviewMode: String, CaseIterable, Identifiable {
    case screenshot = "Screenshot"
    case context = "Accessibility"

    var id: String { rawValue }
}
