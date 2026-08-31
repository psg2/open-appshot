import AppKit
import ApplicationServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

let appBundleIdentifier = "com.psg2.AppShotClipboardPOC"
let customContextType = NSPasteboard.PasteboardType("com.psg2.appshot-context-json")

private enum AppShotError: LocalizedError {
    case noTargetApplication
    case peekabooNotInstalled
    case commandFailed(String)
    case invalidResponse(String)
    case noWindow(String)
    case missingScreenshot

    var errorDescription: String? {
        switch self {
        case .noTargetApplication:
            return "No frontmost application is available."
        case .peekabooNotInstalled:
            return "Peekaboo was not found in /opt/homebrew/bin, /usr/local/bin, or PEEKABOO_CLI_PATH."
        case let .commandFailed(message):
            return message
        case let .invalidResponse(message):
            return "Peekaboo returned an invalid response: \(message)"
        case let .noWindow(appName):
            return "No capturable window was found for \(appName)."
        case .missingScreenshot:
            return "Peekaboo completed without producing a screenshot."
        }
    }
}

struct Snapshot {
    let id: String
    let capturedAt: Date
    let directoryURL: URL
    let screenshotURL: URL
    let accessibilityURL: URL
    let contextURL: URL
    let contextText: String
    let accessibilityJSON: Data
    let appName: String
    let windowTitle: String
    let elementCount: Int
}

private struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: Data
}

final class CaptureEngine {
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let retentionDays: Int

    init(
        baseDirectory: URL = CapturePreferences.captureRootURL,
        retentionDays: Int = CapturePreferences.retentionDays
    ) {
        self.baseDirectory = baseDirectory
        self.retentionDays = retentionDays
    }

    func capture(application: NSRunningApplication) throws -> Snapshot {
        try prepareBaseDirectory()
        try removeExpiredCaptures()

        let id = snapshotDirectoryName()
        let capturedAt = Date()
        let captureDirectory = baseDirectory.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let pid = application.processIdentifier
        let appName = application.localizedName ?? application.bundleIdentifier ?? "PID \(pid)"
        let windowListURL = captureDirectory.appendingPathComponent("windows.json")
        let windowListResult = try runPeekaboo(
            arguments: ["window", "list", "--pid", String(pid), "--json", "--no-remote"],
            captureDirectory: captureDirectory,
            stdoutURL: windowListURL,
            stderrName: "windows.stderr.txt"
        )
        guard windowListResult.status == 0 else {
            throw AppShotError.commandFailed(commandError("window list", result: windowListResult))
        }

        let windowList = try jsonDictionary(windowListResult.stdout)
        guard (windowList["success"] as? Bool) == true,
              let data = windowList["data"] as? [String: Any],
              let windows = data["windows"] as? [[String: Any]]
        else {
            throw AppShotError.invalidResponse(jsonErrorMessage(windowList))
        }

        guard let window = preferredWindow(in: windows),
              let windowID = integer(window["window_id"])
        else {
            throw AppShotError.noWindow(appName)
        }

        let windowTitle = string(window["window_title"]) ?? "Untitled window"
        let screenshotURL = captureDirectory.appendingPathComponent("screenshot.png")
        let accessibilityURL = captureDirectory.appendingPathComponent("accessibility.json")
        let combinedAttemptURL = captureDirectory.appendingPathComponent("combined-attempt.json")
        let combinedResult = try runPeekaboo(
            arguments: [
                "see",
                "--pid", String(pid),
                "--window-id", String(windowID),
                "--json",
                "--depth", "20",
                "--max-elements", "1500",
                "--path", screenshotURL.path,
                "--capture-engine", "cg",
                "--no-remote",
            ],
            captureDirectory: captureDirectory,
            stdoutURL: combinedAttemptURL,
            stderrName: "combined-attempt.stderr.txt"
        )

        let observationData: [String: Any]
        let accessibilityJSON: Data
        let captureStrategy: String
        if combinedResult.status == 0,
           let combinedResponse = try? jsonDictionary(combinedResult.stdout),
           (combinedResponse["success"] as? Bool) == true,
           let combinedData = combinedResponse["data"] as? [String: Any] {
            observationData = combinedData
            accessibilityJSON = combinedResult.stdout
            captureStrategy = "combined screenshot + Accessibility"
        } else {
            let pixelResponseURL = captureDirectory.appendingPathComponent("screenshot-capture.json")
            let pixelResult = try runPeekaboo(
                arguments: [
                    "see",
                    "--pid", String(pid),
                    "--window-id", String(windowID),
                    "--no-elements",
                    "--json",
                    "--path", screenshotURL.path,
                    "--capture-engine", "cg",
                    "--no-remote",
                ],
                captureDirectory: captureDirectory,
                stdoutURL: pixelResponseURL,
                stderrName: "screenshot-capture.stderr.txt"
            )
            guard pixelResult.status == 0,
                  let pixelResponse = try? jsonDictionary(pixelResult.stdout),
                  (pixelResponse["success"] as? Bool) == true
            else {
                throw AppShotError.commandFailed(commandError("screenshot fallback", result: pixelResult))
            }

            let treeResult = try runPeekaboo(
                arguments: [
                    "see",
                    "--pid", String(pid),
                    "--window-id", String(windowID),
                    "--tree",
                    "--no-screenshot",
                    "--json",
                    "--depth", "20",
                    "--max-elements", "1500",
                    "--no-remote",
                ],
                captureDirectory: captureDirectory,
                stdoutURL: accessibilityURL,
                stderrName: "accessibility-capture.stderr.txt"
            )
            guard treeResult.status == 0 else {
                throw AppShotError.commandFailed(commandError("Accessibility fallback", result: treeResult))
            }
            let treeResponse = try jsonDictionary(treeResult.stdout)
            guard (treeResponse["success"] as? Bool) == true,
                  let treeData = treeResponse["data"] as? [String: Any]
            else {
                throw AppShotError.invalidResponse(jsonErrorMessage(treeResponse))
            }
            observationData = treeData
            accessibilityJSON = treeResult.stdout
            captureStrategy = "split screenshot + Accessibility fallback"
        }

        let sanitizedAccessibilityJSON = try sanitizedJSON(accessibilityJSON)
        try sanitizedAccessibilityJSON.write(to: accessibilityURL, options: .atomic)
        if let sanitizedCombinedAttempt = try? sanitizedJSON(combinedResult.stdout) {
            try sanitizedCombinedAttempt.write(to: combinedAttemptURL, options: .atomic)
        }

        guard fileManager.fileExists(atPath: screenshotURL.path) else {
            throw AppShotError.missingScreenshot
        }
        let thumbnailURL = captureDirectory.appendingPathComponent("thumbnail.png")
        try writeThumbnail(from: screenshotURL, to: thumbnailURL)

        let contextText = buildContext(
            appName: appName,
            bundleIdentifier: application.bundleIdentifier,
            pid: pid,
            windowTitle: windowTitle,
            windowID: windowID,
            observation: observationData,
            captureDirectory: captureDirectory,
            captureStrategy: captureStrategy
        )
        let contextURL = captureDirectory.appendingPathComponent("context.md")
        try contextText.write(to: contextURL, atomically: true, encoding: .utf8)

        let metadata = CaptureMetadata(
            id: id,
            capturedAt: capturedAt,
            appName: appName,
            bundleIdentifier: application.bundleIdentifier,
            windowTitle: windowTitle,
            elementCount: integer(observationData["element_count"]) ?? 0,
            captureStrategy: captureStrategy
        )
        let metadataURL = captureDirectory.appendingPathComponent("metadata.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)

        try setPrivatePermissions(
            on: [
                screenshotURL,
                thumbnailURL,
                accessibilityURL,
                contextURL,
                metadataURL,
                windowListURL,
                combinedAttemptURL,
            ]
        )

        return Snapshot(
            id: id,
            capturedAt: capturedAt,
            directoryURL: captureDirectory,
            screenshotURL: screenshotURL,
            accessibilityURL: accessibilityURL,
            contextURL: contextURL,
            contextText: contextText,
            accessibilityJSON: sanitizedAccessibilityJSON,
            appName: appName,
            windowTitle: windowTitle,
            elementCount: integer(observationData["element_count"]) ?? 0
        )
    }

    private func prepareBaseDirectory() throws {
        let alreadyExists = fileManager.fileExists(atPath: baseDirectory.path)
        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !alreadyExists {
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDirectory.path)
        }
    }

    private func removeExpiredCaptures() throws {
        guard retentionDays > 0 else { return }
        let expiration = Date().addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        let urls = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for url in urls {
            let values = try url.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey])
            if values.isDirectory == true, let creationDate = values.creationDate, creationDate < expiration {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func snapshotDirectoryName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.lowercased()
    }

    private func preferredWindow(in windows: [[String: Any]]) -> [String: Any]? {
        let visible = windows.filter { ($0["is_on_screen"] as? Bool) != false }
        if let keyWindow = visible.first(where: { ($0["is_key"] as? Bool) == true }) {
            return keyWindow
        }
        if let frontmostWindow = visible.first(where: { ($0["is_frontmost"] as? Bool) == true }) {
            return frontmostWindow
        }
        let standard = visible.filter { string($0["subrole"]) == "AXStandardWindow" }
        return (standard.isEmpty ? visible : standard).max { windowArea($0) < windowArea($1) }
    }

    private func windowArea(_ window: [String: Any]) -> Double {
        guard let bounds = window["bounds"] as? [String: Any] else { return 0 }
        return double(bounds["width"]) * double(bounds["height"])
    }

    private func buildContext(
        appName: String,
        bundleIdentifier: String?,
        pid: pid_t,
        windowTitle: String,
        windowID: Int,
        observation: [String: Any],
        captureDirectory: URL,
        captureStrategy: String
    ) -> String {
        let elements = observation["ui_elements"] as? [[String: Any]] ?? []
        let maximumElements = 250
        var lines = [
            "# AppShot context",
            "",
            "Captured: \(ISO8601DateFormatter().string(from: Date()))",
            "Application: \(appName)",
            "Bundle ID: \(bundleIdentifier ?? "unknown")",
            "PID: \(pid)",
            "Window: \(windowTitle)",
            "Window ID: \(windowID)",
            "Capture strategy: \(captureStrategy)",
            "Accessibility elements: \(elements.count)",
            "Capture directory: \(captureDirectory.path)",
            "",
            "The clipboard item contains this text and the matching PNG as alternative representations.",
            "The receiving chat decides which representation it accepts.",
            "",
            "## Accessibility summary",
            "",
        ]

        for element in elements.prefix(maximumElements) {
            lines.append(elementLine(element))
        }
        if elements.count > maximumElements {
            lines.append("- [truncated: \(elements.count - maximumElements) additional elements remain in accessibility.json]")
        }

        let truncation = observation["truncation"] as? [String: Any]
        if let truncation, !truncation.isEmpty {
            lines.append("")
            lines.append("Peekaboo truncation metadata: \(compactJSONString(truncation))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func elementLine(_ element: [String: Any]) -> String {
        let role = cleanText(string(element["ax_role"]) ?? string(element["role"]) ?? "element", maximum: 80)
        let secure = role.lowercased().contains("secure") ||
            (string(element["role_description"]) ?? "").lowercased().contains("secure")
        if secure {
            return "- \(role): [secure value redacted]"
        }

        var descriptions: [String] = []
        for key in ["label", "title", "value", "description", "help"] {
            guard let value = string(element[key]) else { continue }
            let cleaned = cleanText(value, maximum: 320)
            guard !cleaned.isEmpty, !descriptions.contains(cleaned) else { continue }
            descriptions.append(cleaned)
        }
        let text = descriptions.isEmpty ? "unnamed" : descriptions.joined(separator: " | ")

        var suffix: [String] = []
        if let bounds = element["bounds"] as? [String: Any] {
            let x = integer(bounds["x"]) ?? 0
            let y = integer(bounds["y"]) ?? 0
            let width = integer(bounds["width"]) ?? 0
            let height = integer(bounds["height"]) ?? 0
            suffix.append("bounds=\(x),\(y),\(width),\(height)")
        }
        if (element["is_actionable"] as? Bool) == true {
            suffix.append("actionable")
        }
        if (element["is_enabled"] as? Bool) == false {
            suffix.append("disabled")
        }
        let metadata = suffix.isEmpty ? "" : " [\(suffix.joined(separator: ", "))]"
        return "- \(role): \(text)\(metadata)"
    }

    private func cleanText(_ value: String, maximum: Int) -> String {
        let oneLine = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if oneLine.count <= maximum { return oneLine }
        return String(oneLine.prefix(maximum)) + "…"
    }

    private func compactJSONString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "unavailable" }
        return text
    }

    private func writeThumbnail(from sourceURL: URL, to destinationURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw AppShotError.missingScreenshot
        }
        let options = [
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

    private func sanitizedJSON(_ source: Data) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: source) as? [String: Any] else {
            throw AppShotError.invalidResponse("the root JSON value is not an object")
        }
        if var data = root["data"] as? [String: Any],
           let elements = data["ui_elements"] as? [[String: Any]] {
            data["ui_elements"] = elements.map { element in
                var sanitized = element
                let role = (string(element["ax_role"]) ?? string(element["role"]) ?? "").lowercased()
                let roleDescription = (string(element["role_description"]) ?? "").lowercased()
                if role.contains("secure") || roleDescription.contains("secure") {
                    sanitized["value"] = "[secure value redacted]"
                }
                return sanitized
            }
            root["data"] = data
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func runPeekaboo(
        arguments: [String],
        captureDirectory: URL,
        stdoutURL: URL,
        stderrName: String
    ) throws -> ProcessResult {
        guard let executableURL = peekabooExecutableURL() else {
            throw AppShotError.peekabooNotInstalled
        }

        try Data().write(to: stdoutURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stdoutURL.path)
        let stderrURL = captureDirectory.appendingPathComponent(stderrName)
        try Data().write(to: stderrURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stderrURL.path)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        try process.run()
        process.waitUntilExit()
        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: try Data(contentsOf: stdoutURL),
            stderr: try Data(contentsOf: stderrURL)
        )
    }

    private func peekabooExecutableURL() -> URL? {
        let environmentPath = ProcessInfo.processInfo.environment["PEEKABOO_CLI_PATH"]
        let paths = [environmentPath, "/opt/homebrew/bin/peekaboo", "/usr/local/bin/peekaboo"].compactMap { $0 }
        return paths.first(where: { fileManager.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    private func jsonDictionary(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppShotError.invalidResponse("the root JSON value is not an object")
        }
        return object
    }

    private func jsonErrorMessage(_ response: [String: Any]) -> String {
        if let error = response["error"] as? [String: Any] {
            return string(error["message"]) ?? compactJSONString(error)
        }
        return "missing success data"
    }

    private func commandError(_ command: String, result: ProcessResult) -> String {
        let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
        let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
        let details = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return "Peekaboo \(command) failed with exit \(result.status). \(cleanText(details, maximum: 1200))"
    }

    private func setPrivatePermissions(on urls: [URL]) throws {
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }
}

enum ClipboardWriter {
    static func copyCombined(_ snapshot: Snapshot) throws {
        let imageData = try Data(contentsOf: snapshot.screenshotURL)
        let item = NSPasteboardItem()
        item.setData(imageData, forType: .png)
        item.setString(snapshot.contextText, forType: .string)
        item.setData(snapshot.accessibilityJSON, forType: customContextType)
        write(item)
    }

    static func copyScreenshot(_ snapshot: Snapshot) throws {
        let imageData = try Data(contentsOf: snapshot.screenshotURL)
        let item = NSPasteboardItem()
        item.setData(imageData, forType: .png)
        write(item)
    }

    static func copyContext(_ snapshot: Snapshot) {
        let item = NSPasteboardItem()
        item.setString(snapshot.contextText, forType: .string)
        item.setData(snapshot.accessibilityJSON, forType: customContextType)
        write(item)
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

    private static func write(_ item: NSPasteboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var model = AppModel()
    private lazy var mainWindowController = MainWindowController(model: model)
    private lazy var settingsWindowController = SettingsWindowController(model: model)
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var hotkeyMenuItem: NSMenuItem!
    private var copyCombinedMenuItem: NSMenuItem!
    private var copyScreenshotMenuItem: NSMenuItem!
    private var copyContextMenuItem: NSMenuItem!
    private var revealMenuItem: NSMenuItem!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?
    private var lastSnapshot: Snapshot?
    private var captureInProgress = false
    private var hotkeyLatched = false
    private var leftOptionDown = false
    private var rightOptionDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        lastExternalApplication = externalApplication(NSWorkspace.shared.frontmostApplication)
        NSApp.setActivationPolicy(.accessory)
        model.captureAction = { [weak self] in self?.triggerCapture() }
        model.showSettingsAction = { [weak self] in self?.showSettings() }
        model.hotkeyChangedAction = { [weak self] in
            self?.installHotkeyMonitor()
            self?.updatePermissionStatus()
        }
        buildMainMenu()
        buildMenuBar()
        observeApplicationActivation()
        installHotkeyMonitor()
        updatePermissionStatus()
        restoreLatestSnapshot()
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard statusMenuItem != nil else { return }
        updatePermissionStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setStatusIcon(symbol: "camera.viewfinder")
        statusItem.button?.toolTip = "Open AppShot"

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        menu.addItem(targetedMenuItem(title: "Open AppShot", action: #selector(showMainWindow)))

        menu.addItem(targetedMenuItem(title: "Capture now", action: #selector(captureNow)))
        hotkeyMenuItem = NSMenuItem(title: "Hotkey: \(model.captureHotkey.displayName)", action: nil, keyEquivalent: "")
        hotkeyMenuItem.isEnabled = false
        menu.addItem(hotkeyMenuItem)
        menu.addItem(.separator())

        copyCombinedMenuItem = targetedMenuItem(title: "Copy combined clipboard", action: #selector(copyCombined))
        copyScreenshotMenuItem = targetedMenuItem(title: "Copy screenshot only", action: #selector(copyScreenshot))
        copyContextMenuItem = targetedMenuItem(title: "Copy Accessibility text only", action: #selector(copyContext))
        revealMenuItem = targetedMenuItem(title: "Reveal last capture", action: #selector(revealLastCapture))
        for item in [copyCombinedMenuItem, copyScreenshotMenuItem, copyContextMenuItem, revealMenuItem] {
            item?.isEnabled = false
            if let item { menu.addItem(item) }
        }

        menu.addItem(.separator())
        menu.addItem(targetedMenuItem(title: "Request missing permissions", action: #selector(requestMissingPermissions)))
        menu.addItem(targetedMenuItem(title: "Open Accessibility settings", action: #selector(openAccessibilitySettings)))
        menu.addItem(targetedMenuItem(title: "Open Screen Recording settings", action: #selector(openScreenRecordingSettings)))
        menu.addItem(targetedMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(targetedMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: "About Open AppShot",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ).target = NSApp
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(targetedMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Hide Open AppShot",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ).target = NSApp
        applicationMenu.addItem(
            withTitle: "Quit Open AppShot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ).target = NSApp
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let captureItem = NSMenuItem()
        let captureMenu = NSMenu(title: "Capture")
        let captureNowItem = targetedMenuItem(title: "Capture Last Active Window", action: #selector(captureNow), keyEquivalent: "c")
        captureNowItem.keyEquivalentModifierMask = [.command, .shift]
        captureMenu.addItem(captureNowItem)
        captureMenu.addItem(.separator())
        captureMenu.addItem(targetedMenuItem(title: "Copy Screenshot and Context", action: #selector(copyCombined)))
        captureMenu.addItem(targetedMenuItem(title: "Copy Screenshot", action: #selector(copyScreenshot)))
        captureMenu.addItem(targetedMenuItem(title: "Copy Accessibility Context", action: #selector(copyContext)))
        captureMenu.addItem(targetedMenuItem(title: "Reveal Last Capture", action: #selector(revealLastCapture)))
        captureItem.submenu = captureMenu
        mainMenu.addItem(captureItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(targetedMenuItem(title: "Close Window", action: #selector(closeKeyWindow), keyEquivalent: "w"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        ).target = NSApp
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    private func targetedMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func observeApplicationActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let external = self?.externalApplication(application)
            else { return }
            self?.lastExternalApplication = external
        }
    }

    private func installHotkeyMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        leftOptionDown = false
        rightOptionDown = false
        hotkeyLatched = false

        let eventMask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleHotkeyEvent(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleHotkeyEvent(event)
            return event
        }
    }

    private func handleHotkeyEvent(_ event: NSEvent) {
        if model.captureHotkey.kind == .keyboard {
            if event.type == .keyDown, model.captureHotkey.matchesKeyDown(event) {
                triggerCapture()
            }
            return
        }

        guard event.type == .flagsChanged else { return }
        let flags = event.modifierFlags
        let raw = flags.rawValue
        let deviceFlags = raw & 0x00000060

        if deviceFlags != 0 {
            leftOptionDown = (raw & 0x00000020) != 0
            rightOptionDown = (raw & 0x00000040) != 0
        } else if event.keyCode == 58 {
            leftOptionDown.toggle()
        } else if event.keyCode == 61 {
            rightOptionDown.toggle()
        }

        if !flags.contains(.option) {
            leftOptionDown = false
            rightOptionDown = false
        }

        if leftOptionDown && rightOptionDown && !hotkeyLatched {
            hotkeyLatched = true
            triggerCapture()
        } else if !leftOptionDown || !rightOptionDown {
            hotkeyLatched = false
        }
    }

    @objc private func captureNow() {
        triggerCapture()
    }

    private func triggerCapture() {
        guard !captureInProgress else { return }
        guard AXIsProcessTrusted() else {
            showFailure("Accessibility permission is not active for this build")
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            showFailure("Screen Recording permission is not active for this build")
            return
        }
        let current = externalApplication(NSWorkspace.shared.frontmostApplication)
        guard let target = current ?? lastExternalApplication else {
            showFailure(AppShotError.noTargetApplication.localizedDescription)
            return
        }

        captureInProgress = true
        model.captureStarted(appName: target.localizedName ?? "application")
        statusMenuItem.title = "Capturing \(target.localizedName ?? "application")…"
        setStatusIcon(symbol: "camera.aperture")
        let captureEngine = CaptureEngine(
            baseDirectory: CapturePreferences.captureRootURL,
            retentionDays: CapturePreferences.retentionDays
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try captureEngine.capture(application: target)
                DispatchQueue.main.async {
                    do {
                        if CapturePreferences.copyAfterCapture {
                            try ClipboardWriter.copyCombined(snapshot)
                        }
                        self.lastSnapshot = snapshot
                        self.captureInProgress = false
                        self.enableSnapshotActions()
                        self.model.captureCompleted(snapshot)
                        self.statusMenuItem.title = CapturePreferences.copyAfterCapture
                            ? "Copied \(snapshot.appName), \(snapshot.elementCount) AX elements"
                            : "Captured \(snapshot.appName), \(snapshot.elementCount) AX elements"
                        self.setStatusIcon(symbol: "checkmark.circle.fill")
                        CapturePreferences.captureSound.play()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.setStatusIcon(symbol: "camera.viewfinder")
                        }
                    } catch {
                        self.captureInProgress = false
                        self.showFailure(error.localizedDescription)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.captureInProgress = false
                    self.showFailure(error.localizedDescription)
                }
            }
        }
    }

    private func enableSnapshotActions() {
        copyCombinedMenuItem.isEnabled = true
        copyScreenshotMenuItem.isEnabled = true
        copyContextMenuItem.isEnabled = true
        revealMenuItem.isEnabled = true
    }

    @objc private func copyCombined() {
        guard let lastSnapshot else { return }
        do {
            try ClipboardWriter.copyCombined(lastSnapshot)
            showCopySuccess("Combined clipboard copied")
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    @objc private func copyScreenshot() {
        guard let lastSnapshot else { return }
        do {
            try ClipboardWriter.copyScreenshot(lastSnapshot)
            showCopySuccess("Screenshot copied")
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    @objc private func copyContext() {
        guard let lastSnapshot else { return }
        ClipboardWriter.copyContext(lastSnapshot)
        showCopySuccess("Accessibility text copied")
    }

    @objc private func revealLastCapture() {
        guard let lastSnapshot else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastSnapshot.contextURL])
    }

    @objc private func requestMissingPermissions() {
        model.requestMissingPermissions()
        updatePermissionStatus()
    }

    @objc private func openAccessibilitySettings() {
        model.openAccessibilitySettings()
    }

    @objc private func openScreenRecordingSettings() {
        model.openScreenRecordingSettings()
    }

    @objc private func showMainWindow() {
        mainWindowController.showWindow(nil)
        mainWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.refreshPermissions()
    }

    @objc private func showSettings() {
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.refreshPermissions()
    }

    @objc private func closeKeyWindow() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updatePermissionStatus() {
        model.refreshPermissions()
        let accessibility = AXIsProcessTrusted()
        let screenRecording = CGPreflightScreenCaptureAccess()
        if accessibility && screenRecording {
            statusMenuItem.title = "Ready. Press \(model.captureHotkey.displayName)"
        } else if !accessibility {
            statusMenuItem.title = "Accessibility permission is required"
        } else {
            statusMenuItem.title = "Screen Recording permission is required"
        }
        hotkeyMenuItem.title = "Hotkey: \(model.captureHotkey.displayName)"
    }

    private func showCopySuccess(_ message: String) {
        statusMenuItem.title = message
        setStatusIcon(symbol: "checkmark.circle.fill")
        CapturePreferences.captureSound.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.setStatusIcon(symbol: "camera.viewfinder")
        }
    }

    private func showFailure(_ message: String) {
        statusMenuItem.title = message
        model.captureFailed(message)
        setStatusIcon(symbol: "exclamationmark.triangle.fill")
        NSSound.beep()
    }

    private func restoreLatestSnapshot() {
        guard let record = model.captures.first, let snapshot = try? record.snapshot() else { return }
        lastSnapshot = snapshot
        enableSnapshotActions()
    }

    private func setStatusIcon(symbol: String) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Open AppShot")
    }

    private func externalApplication(_ application: NSRunningApplication?) -> NSRunningApplication? {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.bundleIdentifier != appBundleIdentifier
        else { return nil }
        return application
    }
}

private func runningApplication(from arguments: [String]) -> NSRunningApplication? {
    if let pidIndex = arguments.firstIndex(of: "--pid"), arguments.indices.contains(pidIndex + 1),
       let pid = Int32(arguments[pidIndex + 1]) {
        return NSRunningApplication(processIdentifier: pid)
    }
    return NSWorkspace.shared.frontmostApplication
}

private let arguments = CommandLine.arguments
if arguments.contains("--accessibility-status") {
    print("trusted=\(AXIsProcessTrusted())")
    exit(EXIT_SUCCESS)
}

if arguments.contains("--permissions-status") {
    print("accessibility=\(AXIsProcessTrusted())")
    print("screen_recording=\(CGPreflightScreenCaptureAccess())")
    exit(EXIT_SUCCESS)
}

if arguments.contains("--inspect-clipboard") {
    print(ClipboardWriter.describeClipboard())
    exit(EXIT_SUCCESS)
}

if arguments.contains("--capture-root") {
    print(CapturePreferences.captureRootURL.path)
    exit(EXIT_SUCCESS)
}

if arguments.contains("--history-count") {
    print(CaptureHistory.load().count)
    exit(EXIT_SUCCESS)
}

if arguments.contains("--hotkey-json") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(CapturePreferences.captureHotkey),
       let value = String(data: data, encoding: .utf8) {
        print(value)
        exit(EXIT_SUCCESS)
    }
    exit(EXIT_FAILURE)
}

if arguments.contains("--capture-once") {
    do {
        guard let target = runningApplication(from: arguments) else {
            throw AppShotError.noTargetApplication
        }
        let snapshot = try CaptureEngine().capture(application: target)
        try ClipboardWriter.copyCombined(snapshot)
        print("capture_directory=\(snapshot.directoryURL.path)")
        print("application=\(snapshot.appName)")
        print("window=\(snapshot.windowTitle)")
        print("elements=\(snapshot.elementCount)")
        print(ClipboardWriter.describeClipboard())
        exit(EXIT_SUCCESS)
    } catch {
        fputs("error=\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

private let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.run()
