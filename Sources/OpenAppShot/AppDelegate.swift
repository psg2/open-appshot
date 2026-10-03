import AppKit
import ApplicationServices
import Foundation
import ImageIO
import OpenAppShotCore
import UniformTypeIdentifiers

let appBundleIdentifier = "com.psg2.AppShotClipboardPOC"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
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
        model.historyChangedAction = { [weak self] in
            self?.restoreLatestSnapshot()
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
        ]
        if let action = menuItem.action, selectionActions.contains(action) {
            return mainWindowController.window?.isKeyWindow == true && model.selectedCapture != nil
        }
        if menuItem.action == #selector(deleteSelectedCapture) {
            return mainWindowController.window?.isKeyWindow == true && model.selectedCapture?.canDelete == true
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
                        self.setSnapshotActionsEnabled(true)
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

    private func setSnapshotActionsEnabled(_ enabled: Bool) {
        copyModeMenuItem.isEnabled = enabled
        copyScreenshotMenuItem.isEnabled = enabled
        copyContextMenuItem.isEnabled = enabled
        revealMenuItem.isEnabled = enabled
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
        guard let record = model.captures.first, let snapshot = try? record.snapshot() else {
            lastSnapshot = nil
            setSnapshotActionsEnabled(false)
            return
        }
        lastSnapshot = snapshot
        setSnapshotActionsEnabled(true)
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
