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

struct CaptureHotkey: Codable, Equatable {
    enum Kind: String, Codable {
        case dualOption
        case keyboard
    }

    let kind: Kind
    let keyCode: UInt16?
    let modifierRawValue: UInt
    let keyDisplay: String?

    static let dualOption = CaptureHotkey(
        kind: .dualOption,
        keyCode: nil,
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        keyDisplay: nil
    )

    static let supportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue).intersection(Self.supportedModifiers)
    }

    var displayName: String {
        if kind == .dualOption { return "Left ⌥ + Right ⌥" }
        return modifierSymbols + (keyDisplay ?? "Key")
    }

    var compactDisplayName: String {
        if kind == .dualOption { return "L⌥ + R⌥" }
        return displayName
    }

    func matchesKeyDown(_ event: NSEvent) -> Bool {
        guard kind == .keyboard, let keyCode else { return false }
        let eventModifiers = event.modifierFlags.intersection(Self.supportedModifiers)
        return event.keyCode == keyCode && eventModifiers == modifiers && !event.isARepeat
    }

    static func keyboard(event: NSEvent) -> CaptureHotkey? {
        let modifiers = event.modifierFlags.intersection(supportedModifiers)
        let requiredModifiers = modifiers.intersection([.command, .option, .control])
        guard !requiredModifiers.isEmpty else { return nil }

        return CaptureHotkey(
            kind: .keyboard,
            keyCode: event.keyCode,
            modifierRawValue: modifiers.rawValue,
            keyDisplay: displayKey(for: event)
        )
    }

    static func isReserved(_ hotkey: CaptureHotkey) -> Bool {
        guard hotkey.kind == .keyboard,
              let keyCode = hotkey.keyCode
        else { return false }

        switch hotkey.modifiers {
        case [.command]:
            return [0, 4, 8, 12, 13, 15, 43, 46].contains(keyCode)
        case [.command, .shift]:
            return [8, 15].contains(keyCode)
        case [.command, .option]:
            return [8, 17, 34].contains(keyCode)
        default:
            return false
        }
    }

    private var modifierSymbols: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    private static func displayKey(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "Forward Delete"
        case 119: return "End"
        case 121: return "Page Down"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
            return characters?.isEmpty == false ? characters!.uppercased() : "Key (event.keyCode)"
        }
    }
}

enum CaptureSound: String, CaseIterable, Identifiable {
    case none = ""
    case glass = "Glass"
    case hero = "Hero"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case submarine = "Submarine"
    case tink = "Tink"

    var id: String { rawValue }
    var displayName: String { self == .none ? "None" : rawValue }

    func play() {
        guard self != .none else { return }
        NSSound(named: rawValue)?.play()
    }
}

enum CapturePreferences {
    private static let defaults = UserDefaults.standard
    private static let captureDirectoryKey = "captureDirectoryPath"
    private static let retentionDaysKey = "captureRetentionDays"
    private static let copyAfterCaptureKey = "copyAfterCapture"
    private static let legacyPlaySoundKey = "playCaptureSound"
    private static let captureSoundKey = "captureSoundName"
    private static let captureHotkeyKey = "captureHotkey"

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

    static var captureSound: CaptureSound {
        get {
            if let stored = defaults.string(forKey: captureSoundKey), let sound = CaptureSound(rawValue: stored) {
                return sound
            }
            if defaults.object(forKey: legacyPlaySoundKey) != nil, !defaults.bool(forKey: legacyPlaySoundKey) {
                return .none
            }
            return .glass
        }
        set { defaults.set(newValue.rawValue, forKey: captureSoundKey) }
    }

    static var captureHotkey: CaptureHotkey {
        get {
            guard let data = defaults.data(forKey: captureHotkeyKey),
                  let hotkey = try? JSONDecoder().decode(CaptureHotkey.self, from: data),
                  !CaptureHotkey.isReserved(hotkey)
            else { return .dualOption }
            return hotkey
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: captureHotkeyKey)
        }
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
    @Published var deletionCandidate: CaptureRecord?
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
    @Published var captureSound = CapturePreferences.captureSound {
        didSet { CapturePreferences.captureSound = captureSound }
    }
    @Published var captureHotkey = CapturePreferences.captureHotkey {
        didSet {
            CapturePreferences.captureHotkey = captureHotkey
            hotkeyChangedAction?()
            if isReady { statusMessage = "Ready for \(captureHotkey.displayName)" }
        }
    }

    var captureAction: (() -> Void)?
    var showSettingsAction: (() -> Void)?
    var hotkeyChangedAction: (() -> Void)?

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
        statusMessage = isReady ? "Ready for \(captureHotkey.displayName)" : "Two permissions are needed before capture"
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

    func requestDeletion(_ record: CaptureRecord) {
        deletionCandidate = record
    }

    func cancelDeletion() {
        deletionCandidate = nil
    }

    func confirmDeletion() {
        guard let record = deletionCandidate else { return }
        deletionCandidate = nil
        delete(record)
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

    func resetCaptureHotkey() {
        captureHotkey = .dualOption
    }

    func previewCaptureSound() {
        captureSound.play()
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
            captureSound.play()
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
