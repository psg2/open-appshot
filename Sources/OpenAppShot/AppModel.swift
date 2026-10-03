import AppKit
import ApplicationServices
import Combine
import Foundation
import OpenAppShotCore

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
    @Published var clipboardMode = CapturePreferences.clipboardMode {
        didSet {
            CapturePreferences.clipboardMode = clipboardMode
            clipboardModeChangedAction?()
        }
    }
    @Published var captureSound = CapturePreferences.captureSound {
        didSet { CapturePreferences.captureSound = captureSound }
    }
    @Published var confirmBeforeDeleting = CapturePreferences.confirmBeforeDeleting {
        didSet {
            CapturePreferences.confirmBeforeDeleting = confirmBeforeDeleting
            if !confirmBeforeDeleting { deletionCandidate = nil }
        }
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
    var clipboardModeChangedAction: (() -> Void)?
    var historyChangedAction: (() -> Void)?

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
        historyChangedAction?()
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

    func copyUsingClipboardMode(_ record: CaptureRecord) {
        performCopy(label: "Copied using \(clipboardMode.displayName)") {
            try ClipboardWriter.copy(record.snapshot(), mode: clipboardMode)
        }
    }

    func copyFullContext(_ record: CaptureRecord) {
        performCopy(label: "Image and full Accessibility copied") {
            try ClipboardWriter.copy(record.snapshot(), mode: .imageAndFullContext)
        }
    }

    func copyScreenshot(_ record: CaptureRecord) {
        performCopy(label: "Screenshot copied") {
            try ClipboardWriter.copyScreenshot(record.snapshot())
        }
    }

    func copyContext(_ record: CaptureRecord) {
        performCopy(label: "Accessibility context copied") {
            try ClipboardWriter.copyContext(record.snapshot())
        }
    }

    func reveal(_ record: CaptureRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([record.contextURL])
    }

    func requestDeletion(_ record: CaptureRecord) {
        guard record.canDelete else {
            statusMessage = "This unverified legacy capture is read-only"
            return
        }
        if confirmBeforeDeleting {
            deletionCandidate = record
        } else {
            delete(record)
        }
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
        guard record.canDelete, record.hasVerifiedOwnership else {
            statusMessage = "This unverified legacy capture is read-only"
            return
        }
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
        panel.directoryURL = CapturePreferences.storageContainerURL ?? storageURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        CapturePreferences.selectStorageContainer(url.path)
        storageURL = CapturePreferences.captureRootURL
        reloadHistory()
    }

    func useDefaultStorageDirectory() {
        CapturePreferences.selectStorageContainer(nil)
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
