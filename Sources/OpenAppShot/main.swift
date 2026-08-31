import AppKit
import ApplicationServices
import Foundation
import ImageIO
import UniformTypeIdentifiers

let appBundleIdentifier = "com.psg2.AppShotClipboardPOC"
let customContextType = NSPasteboard.PasteboardType("com.psg2.appshot-context-json")

private enum AppShotError: LocalizedError {
    case noTargetApplication
    case commandFailed(String)
    case missingScreenshot
    case invalidArguments(String)

    var errorDescription: String? {
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
    let captureStrategy: String
}

final class CaptureEngine {
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let retentionDays: Int
    private let observationEngine: NativeObservationEngine

    init(
        baseDirectory: URL = CapturePreferences.captureRootURL,
        retentionDays: Int = CapturePreferences.retentionDays,
        observationEngine: NativeObservationEngine = NativeObservationEngine()
    ) {
        self.baseDirectory = baseDirectory
        self.retentionDays = retentionDays
        self.observationEngine = observationEngine
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
            observation: observation,
            captureDirectory: captureDirectory,
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

        return Snapshot(
            id: id,
            capturedAt: capturedAt,
            directoryURL: captureDirectory,
            screenshotURL: screenshotURL,
            accessibilityURL: accessibilityURL,
            contextURL: contextURL,
            contextText: contextText,
            accessibilityJSON: accessibilityJSON,
            appName: appName,
            windowTitle: observation.window.title,
            elementCount: observation.elements.count,
            captureStrategy: observation.captureStrategy
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

    private func buildContext(
        appName: String,
        bundleIdentifier: String?,
        pid: pid_t,
        observation: ObservationResult,
        captureDirectory: URL,
        captureStrategy: String
    ) -> String {
        var lines = [
            "# AppShot context",
            "",
            "Captured: \(ISO8601DateFormatter().string(from: Date()))",
            "Application: \(appName)",
            "Bundle ID: \(bundleIdentifier ?? "unknown")",
            "PID: \(pid)",
            "Window: \(observation.window.title)",
            "Window ID: \(observation.window.id)",
            "Observation engine: Native macOS",
            "Capture strategy: \(captureStrategy)",
            "Accessibility elements: \(observation.elements.count)",
            "Capture directory: \(captureDirectory.path)",
            "",
            "The clipboard item contains this text and the matching PNG as alternative representations.",
            "The receiving chat decides which representation it accepts.",
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

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private lazy var model = AppModel()
    private lazy var mainWindowController = MainWindowController(model: model)
    private lazy var settingsWindowController = SettingsWindowController(model: model)
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var hotkeyMenuItem: NSMenuItem!
    private var copyModeMenuItem: NSMenuItem!
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
        model.clipboardModeChangedAction = { [weak self] in
            self?.updateClipboardModeMenuItem()
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

        copyModeMenuItem = targetedMenuItem(
            title: "Copy using \(model.clipboardMode.displayName)",
            action: #selector(copyUsingClipboardMode)
        )
        copyScreenshotMenuItem = targetedMenuItem(title: "Copy screenshot only", action: #selector(copyScreenshot))
        copyContextMenuItem = targetedMenuItem(title: "Copy Accessibility text only", action: #selector(copyContext))
        revealMenuItem = targetedMenuItem(title: "Reveal last capture", action: #selector(revealLastCapture))
        for item in [copyModeMenuItem, copyScreenshotMenuItem, copyContextMenuItem, revealMenuItem] {
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
        captureMenu.addItem(
            targetedMenuItem(
                title: "Capture Last Active Window",
                action: #selector(captureNow),
                keyEquivalent: "c",
                modifierMask: [.command, .shift]
            )
        )
        captureMenu.addItem(.separator())
        captureMenu.addItem(
            targetedMenuItem(
                title: "Copy Using Clipboard Mode",
                action: #selector(copySelectedUsingClipboardMode),
                keyEquivalent: "c",
                modifierMask: [.command, .option]
            )
        )
        captureMenu.addItem(
            targetedMenuItem(
                title: "Copy Screenshot",
                action: #selector(copySelectedScreenshot),
                keyEquivalent: "i",
                modifierMask: [.command, .option]
            )
        )
        captureMenu.addItem(
            targetedMenuItem(
                title: "Copy Accessibility Context",
                action: #selector(copySelectedContext),
                keyEquivalent: "t",
                modifierMask: [.command, .option]
            )
        )
        captureMenu.addItem(.separator())
        captureMenu.addItem(
            targetedMenuItem(
                title: "Reveal in Finder",
                action: #selector(revealSelectedCapture),
                keyEquivalent: "r",
                modifierMask: [.command, .shift]
            )
        )
        captureMenu.addItem(
            targetedMenuItem(
                title: "Reload History",
                action: #selector(reloadHistory),
                keyEquivalent: "r"
            )
        )
        captureMenu.addItem(.separator())
        captureMenu.addItem(
            targetedMenuItem(
                title: "Delete Capture…",
                action: #selector(deleteSelectedCapture),
                keyEquivalent: "\u{7F}",
                modifierMask: []
            )
        )
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
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if let modifierMask { item.keyEquivalentModifierMask = modifierMask }
        item.target = self
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(captureNow) {
            return model.isReady && !captureInProgress
        }

        let selectionActions: [Selector] = [
            #selector(copySelectedUsingClipboardMode),
            #selector(copySelectedScreenshot),
            #selector(copySelectedContext),
            #selector(revealSelectedCapture),
            #selector(deleteSelectedCapture),
        ]
        if let action = menuItem.action, selectionActions.contains(action) {
            return mainWindowController.window?.isKeyWindow == true && model.selectedCapture != nil
        }

        if menuItem.action == #selector(reloadHistory) {
            return mainWindowController.window?.isKeyWindow == true
        }
        return true
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
                            try ClipboardWriter.copy(snapshot, mode: CapturePreferences.clipboardMode)
                        }
                        self.lastSnapshot = snapshot
                        self.captureInProgress = false
                        self.enableSnapshotActions()
                        self.model.captureCompleted(snapshot)
                        self.statusMenuItem.title =
                            CapturePreferences.copyAfterCapture
                            ? "Copied \(snapshot.appName) using \(CapturePreferences.clipboardMode.displayName)"
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
        copyModeMenuItem.isEnabled = true
        copyScreenshotMenuItem.isEnabled = true
        copyContextMenuItem.isEnabled = true
        revealMenuItem.isEnabled = true
    }

    @objc private func copyUsingClipboardMode() {
        guard let lastSnapshot else { return }
        do {
            try ClipboardWriter.copy(lastSnapshot, mode: model.clipboardMode)
            showCopySuccess("Copied using \(model.clipboardMode.displayName)")
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
        do {
            try ClipboardWriter.copyContext(lastSnapshot)
            showCopySuccess("Accessibility text copied")
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    @objc private func revealLastCapture() {
        guard let lastSnapshot else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastSnapshot.contextURL])
    }

    @objc private func copySelectedUsingClipboardMode() {
        guard let capture = model.selectedCapture else { return }
        model.copyUsingClipboardMode(capture)
    }

    @objc private func copySelectedScreenshot() {
        guard let capture = model.selectedCapture else { return }
        model.copyScreenshot(capture)
    }

    @objc private func copySelectedContext() {
        guard let capture = model.selectedCapture else { return }
        model.copyContext(capture)
    }

    @objc private func revealSelectedCapture() {
        guard let capture = model.selectedCapture else { return }
        model.reveal(capture)
    }

    @objc private func reloadHistory() {
        model.reloadHistory()
    }

    @objc private func deleteSelectedCapture() {
        guard let capture = model.selectedCapture else { return }
        model.requestDeletion(capture)
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

    private func updateClipboardModeMenuItem() {
        copyModeMenuItem.title = "Copy using \(model.clipboardMode.displayName)"
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
        let pid = Int32(arguments[pidIndex + 1])
    {
        return NSRunningApplication(processIdentifier: pid)
    }
    return NSWorkspace.shared.frontmostApplication
}

private func argumentValue(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

private func clipboardMode(from arguments: [String], default defaultMode: ClipboardMode) throws -> ClipboardMode {
    guard let value = argumentValue(after: "--clipboard-mode", in: arguments) else { return defaultMode }
    switch value {
    case "full", ClipboardMode.imageAndFullContext.rawValue:
        return .imageAndFullContext
    case "references", ClipboardMode.imageAndReferences.rawValue:
        return .imageAndReferences
    case "image", ClipboardMode.imageOnly.rawValue:
        return .imageOnly
    case "accessibility", ClipboardMode.accessibilityOnly.rawValue:
        return .accessibilityOnly
    default:
        throw AppShotError.invalidArguments("Unknown clipboard mode: \(value)")
    }
}

private func snapshot(atDirectoryPath path: String) throws -> Snapshot {
    let requestedURL = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    guard
        let record = CaptureHistory.load().first(where: {
            $0.directoryURL.standardizedFileURL == requestedURL
        })
    else {
        throw AppShotError.invalidArguments("Capture was not found in history: \(path)")
    }
    return try record.snapshot()
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

if arguments.contains("--clipboard-text") {
    print(ClipboardWriter.clipboardText(), terminator: "")
    exit(EXIT_SUCCESS)
}

if let capturePath = argumentValue(after: "--copy-capture", in: arguments) {
    do {
        let mode = try clipboardMode(from: arguments, default: .imageAndFullContext)
        let snapshot = try snapshot(atDirectoryPath: capturePath)
        try ClipboardWriter.copy(snapshot, mode: mode)
        print("clipboard_mode=\(mode.rawValue)")
        print(ClipboardWriter.describeClipboard())
        exit(EXIT_SUCCESS)
    } catch {
        fputs("error=\(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
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
        let value = String(data: data, encoding: .utf8)
    {
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
        let mode = try clipboardMode(from: arguments, default: .imageAndFullContext)
        let snapshot = try CaptureEngine().capture(application: target)
        try ClipboardWriter.copy(snapshot, mode: mode)
        print("capture_directory=\(snapshot.directoryURL.path)")
        print("application=\(snapshot.appName)")
        print("window=\(snapshot.windowTitle)")
        print("elements=\(snapshot.elementCount)")
        print("engine=native")
        print("strategy=\(snapshot.captureStrategy)")
        print("clipboard_mode=\(mode.rawValue)")
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
