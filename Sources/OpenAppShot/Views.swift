import AppKit
import OpenAppShotCore
import SwiftUI

final class MainWindowController: NSWindowController {
    init(model: AppModel) {
        let rootView = OpenAppShotView().environmentObject(model)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Open AppShot"
        window.setContentSize(NSSize(width: 1120, height: 720))
        window.minSize = NSSize(width: 880, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("OpenAppShotMainWindow")
        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SettingsWindowController: NSWindowController {
    init(model: AppModel) {
        let rootView = OpenAppShotSettingsView().environmentObject(model)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Open AppShot Settings"
        window.setContentSize(NSSize(width: 620, height: 680))
        window.styleMask = [.titled, .closable]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct OpenAppShotView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            CaptureSidebar()
        } detail: {
            Group {
                if let capture = model.selectedCapture {
                    CaptureDetail(capture: capture)
                } else {
                    FirstCaptureView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !model.isReady {
                    PermissionBanner()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.requestCapture()
                } label: {
                    if model.captureInProgress {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Capture", systemImage: "camera.viewfinder")
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.captureInProgress || !model.isReady)
                .help("Capture the last active window (⇧⌘C)")

                Button {
                    model.reloadHistory()
                } label: {
                    Label("Reload History", systemImage: "arrow.clockwise")
                }
                .help("Reload capture history")
            }
        }
        .onDeleteCommand {
            guard let capture = model.selectedCapture else { return }
            model.requestDeletion(capture)
        }
        .confirmationDialog(
            "Delete this capture?",
            isPresented: Binding(
                get: { model.deletionCandidate != nil },
                set: { if !$0 { model.cancelDeletion() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Capture", role: .destructive) { model.confirmDeletion() }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { model.cancelDeletion() }
                .keyboardShortcut(.cancelAction)
        } message: {
            if let capture = model.deletionCandidate {
                Text("This removes the screenshot and Accessibility context from \(capture.directoryURL.path).")
            }
        }
        .onAppear { model.refreshPermissions() }
    }
}

private struct CaptureSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.selectedCaptureID) {
            Section("Captures") {
                ForEach(model.captures) { capture in
                    CaptureRow(capture: capture, isSelected: model.selectedCaptureID == capture.id)
                        .tag(capture.id)
                        .contextMenu {
                            Button("Copy Using \(model.clipboardMode.displayName)") {
                                model.copyUsingClipboardMode(capture)
                            }
                            Button("Reveal in Finder") { model.reveal(capture) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Open AppShot")
        .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 340)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
    }
}

private struct CaptureRow: View {
    @EnvironmentObject private var model: AppModel
    let capture: CaptureRecord
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnailURL = capture.thumbnailURL, let image = NSImage(contentsOf: thumbnailURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "macwindow")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, height: 40)
            .background(Color(nsColor: .quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(capture.metadata.appName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(capture.metadata.windowTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(capture.metadata.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    if capture.isLegacy {
                        Text(capture.canDelete ? "Legacy" : "Read-only legacy")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)
            if capture.canDelete && (isHovering || isSelected) {
                Button {
                    model.requestDeletion(capture)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete capture (⌫)")
                .accessibilityLabel("Delete \(capture.metadata.appName) capture")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

private struct SidebarFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isReady ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(model.statusMessage)
                    .font(.caption)
                    .lineLimit(2)
            }
            Button {
                model.showSettingsAction?()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.bar)
    }
}

private struct PermissionBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Finish capture setup")
                    .font(.headline)
                Text(missingPermissionText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Button("Request Permissions") { model.requestMissingPermissions() }
            Button("Open Settings") {
                if !model.accessibilityGranted {
                    model.openAccessibilitySettings()
                } else {
                    model.openScreenRecordingSettings()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var missingPermissionText: String {
        if !model.accessibilityGranted && !model.screenRecordingGranted {
            return "Allow Accessibility for the hotkey and Screen Recording for window pixels."
        }
        if !model.accessibilityGranted {
            return "Allow Accessibility so the global two-Option hotkey and UI context can be read."
        }
        return "Allow Screen Recording so the selected window can be captured."
    }
}

private struct FirstCaptureView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            HotkeyIllustration(hotkey: model.captureHotkey)

            VStack(spacing: 8) {
                Text(model.isReady ? "Capture your first window" : "Set up Open AppShot")
                    .font(.title2.weight(.semibold))
                Text(
                    model.isReady
                        ? "Focus another app, then press \(model.captureHotkey.displayName). The screenshot and Accessibility context will appear here."
                        : "Grant the two macOS permissions above. Open AppShot only observes a window after you trigger a capture."
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            }

            if model.isReady {
                Button("Capture Last Active Window") { model.requestCapture() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct HotkeyIllustration: View {
    let hotkey: CaptureHotkey

    var body: some View {
        if hotkey.kind == .dualOption {
            HStack(spacing: 10) {
                Keycap(label: "⌥", side: "L")
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Keycap(label: "⌥", side: "R")
            }
        } else {
            Text(hotkey.displayName)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .padding(.horizontal, 22)
                .frame(height: 52)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.13), radius: 0, y: 3)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
        }
    }
}

private struct Keycap: View {
    let label: String
    let side: String

    var body: some View {
        VStack(spacing: 1) {
            Text(label).font(.system(size: 26, weight: .medium, design: .rounded))
            Text(side).font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(width: 58, height: 52)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.13), radius: 0, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }
}

private struct CaptureDetail: View {
    @EnvironmentObject private var model: AppModel
    let capture: CaptureRecord

    var body: some View {
        VStack(spacing: 0) {
            CaptureHeader(capture: capture)
            Divider()

            Group {
                switch model.previewMode {
                case .screenshot:
                    ScreenshotPreview(capture: capture)
                case .context:
                    ContextPreview(capture: capture)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            ContextRail(capture: capture)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Preview", selection: $model.previewMode) {
                    ForEach(CapturePreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            ToolbarItemGroup(placement: .secondaryAction) {
                Menu {
                    Button("Copy Using \(model.clipboardMode.displayName)") {
                        model.copyUsingClipboardMode(capture)
                    }
                    Divider()
                    Button("Copy Image + Full Accessibility") { model.copyFullContext(capture) }
                    Button("Copy Screenshot") { model.copyScreenshot(capture) }
                    Button("Copy Accessibility Context") { model.copyContext(capture) }
                    Divider()
                    Button("Reveal in Finder") { model.reveal(capture) }
                    Button("Delete Capture…", role: .destructive) { model.requestDeletion(capture) }
                        .disabled(!capture.canDelete)
                } label: {
                    Label("Capture Actions", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}

private struct CaptureHeader: View {
    let capture: CaptureRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(capture.metadata.windowTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(capture.metadata.appName) · \(capture.metadata.capturedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ScreenshotPreview: View {
    let capture: CaptureRecord

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Group {
                    if let image = NSImage(contentsOf: capture.screenshotURL) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: max(proxy.size.width - 56, 200), maxHeight: max(proxy.size.height - 56, 200))
                    } else {
                        ContentUnavailableView("Screenshot unavailable", systemImage: "rectangle.slash")
                    }
                }
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                .padding(28)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct ContextPreview: View {
    let capture: CaptureRecord

    var body: some View {
        ScrollView {
            Text((try? String(contentsOf: capture.contextURL, encoding: .utf8)) ?? "Context is unavailable.")
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct ContextRail: View {
    let capture: CaptureRecord

    var body: some View {
        HStack(spacing: 0) {
            ContextMetric(
                icon: "photo",
                label: "Pixels",
                value: pixelSize
            )
            Divider().frame(height: 34)
            ContextMetric(
                icon: "point.3.connected.trianglepath.dotted",
                label: "Accessibility",
                value: "\(capture.metadata.elementCount) elements"
            )
            Divider().frame(height: 34)
            ContextMetric(
                icon: "internaldrive",
                label: capture.isLegacy ? "Legacy storage" : "Capture storage",
                value: capture.directoryURL.deletingLastPathComponent().lastPathComponent
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var pixelSize: String {
        guard let image = NSImage(contentsOf: capture.screenshotURL) else { return "Unavailable" }
        let representation = image.representations.first
        let width = representation?.pixelsWide ?? Int(image.size.width)
        let height = representation?.pixelsHigh ?? Int(image.size.height)
        return "\(width) × \(height)"
    }
}

private struct ContextMetric: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 14)
    }
}

struct OpenAppShotSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var recordingHotkey = false

    var body: some View {
        Form {
            Section {
                PermissionStatusRow(
                    title: "Accessibility",
                    detail: "Reads the hotkey and UI context",
                    granted: model.accessibilityGranted,
                    openSettings: model.openAccessibilitySettings
                )
                PermissionStatusRow(
                    title: "Screen Recording",
                    detail: "Captures the selected window",
                    granted: model.screenRecordingGranted,
                    openSettings: model.openScreenRecordingSettings
                )
                HStack {
                    Button("Request Missing Permissions") { model.requestMissingPermissions() }
                    Button("Check Again") { model.refreshPermissions() }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Open AppShot reads a window only after you press the capture hotkey or choose Capture.")
            }

            Section {
                LabeledContent("Hotkey") {
                    HStack(spacing: 6) {
                        HotkeyBadge(hotkey: model.captureHotkey)
                        Button("Record…") { recordingHotkey = true }
                            .controlSize(.small)
                        Button("Reset") { model.resetCaptureHotkey() }
                            .controlSize(.small)
                            .disabled(model.captureHotkey == .dualOption)
                    }
                }
                Toggle("Copy after capture", isOn: $model.copyAfterCapture)
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Clipboard content", selection: $model.clipboardMode) {
                        ForEach(ClipboardMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Text(model.clipboardMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ClipboardModeReceipt(mode: model.clipboardMode)
                }
                LabeledContent("Sound") {
                    HStack(spacing: 6) {
                        Picker("Sound", selection: $model.captureSound) {
                            ForEach(CaptureSound.allCases) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        Button {
                            model.previewCaptureSound()
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .controlSize(.small)
                        .disabled(model.captureSound == .none)
                        .help("Preview sound")
                    }
                }
            } header: {
                Text("Capture")
            } footer: {
                Text(
                    "The clipboard mode applies to automatic copies and the main Copy command. Explicit image-only and Accessibility-only commands remain available."
                )
            }

            Section {
                Picker("Keep captures", selection: $model.retentionDays) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(0)
                }
                Toggle("Confirm before deleting captures", isOn: $model.confirmBeforeDeleting)
            } header: {
                Text("History")
            } footer: {
                Text("Turn off confirmation to make Delete and the trash button remove a capture immediately.")
            }

            Section {
                LabeledContent("Folder") {
                    Text(model.storageURL.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Choose Folder…") { model.chooseStorageDirectory() }
                    Button("Use Default") { model.useDefaultStorageDirectory() }
                        .disabled(model.storageURL.standardizedFileURL == CapturePreferences.defaultCaptureRootURL.standardizedFileURL)
                    Button("Reveal in Finder") { model.revealStorageDirectory() }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text(
                    "New captures use this folder. Previously selected Open AppShot folders remain visible and follow the retention setting. Unverified POC captures are read-only."
                )
            }

            Section {
                LabeledContent("Network") { Text("No uploads").foregroundStyle(.secondary) }
                LabeledContent("UI actions") { Text("Capture only").foregroundStyle(.secondary) }
                LabeledContent("Secure fields") { Text("Redacted from AX output").foregroundStyle(.secondary) }
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 680)
        .onAppear { model.refreshPermissions() }
        .sheet(isPresented: $recordingHotkey) {
            ShortcutRecorderSheet()
                .environmentObject(model)
        }
    }
}

private struct ClipboardModeReceipt: View {
    let mode: ClipboardMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 4) {
                    Image(systemName: item.systemImage)
                        .foregroundStyle(.blue)
                    Text(item.label)
                }
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .overlay {
                    Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clipboard contains \(items.map(\.label).joined(separator: ", "))")
    }

    private var items: [ClipboardReceiptItem] {
        var result: [ClipboardReceiptItem] = []
        if mode.includesImage {
            result.append(ClipboardReceiptItem(label: "Image", systemImage: "photo"))
        }
        if mode.includesFullContext {
            result.append(ClipboardReceiptItem(label: "AX text", systemImage: "text.alignleft"))
        }
        if mode.includesStructuredContext {
            result.append(ClipboardReceiptItem(label: "AX JSON", systemImage: "point.3.connected.trianglepath.dotted"))
        }
        if mode.includesFileReferences {
            result.append(ClipboardReceiptItem(label: "File paths", systemImage: "link"))
        }
        return result
    }
}

private struct ClipboardReceiptItem: Identifiable {
    let label: String
    let systemImage: String

    var id: String { label }
}

private struct HotkeyBadge: View {
    let hotkey: CaptureHotkey

    var body: some View {
        Text(hotkey.compactDisplayName)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
    }
}

private struct ShortcutRecorderSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: CaptureHotkey?
    @State private var message = "Press a shortcut with at least two modifiers."

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)

            VStack(spacing: 6) {
                Text("Record capture shortcut")
                    .font(.title2.weight(.semibold))
                Text("Press both Option keys, or a key combination with at least two modifiers including Command, Option, or Control.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            ShortcutRecorderView(candidate: $candidate, message: $message)
                .frame(width: 420, height: 78)

            Text(candidate?.displayName ?? message)
                .font(.system(.body, design: .rounded).weight(candidate == nil ? .regular : .semibold))
                .foregroundStyle(candidate == nil ? .secondary : .primary)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use Shortcut") {
                    guard let candidate else { return }
                    model.captureHotkey = candidate
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(candidate == nil)
            }
        }
        .padding(28)
        .frame(width: 500)
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var candidate: CaptureHotkey?
    @Binding var message: String

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onResult = { hotkey, error in
            DispatchQueue.main.async {
                candidate = hotkey
                if let error { message = error }
            }
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {}
}

private final class ShortcutRecorderNSView: NSView {
    var onResult: ((CaptureHotkey?, String?) -> Void)?
    private let label = NSTextField(labelWithString: "Listening for shortcut…")

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
        updateColors()
        setAccessibilityLabel("Shortcut recorder")
        setAccessibilityHelp("Press a shortcut to use for capture")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func keyDown(with event: NSEvent) {
        guard let hotkey = CaptureHotkey.keyboard(event: event) else {
            onResult?(nil, "Use at least two modifiers, including Command, Option, or Control.")
            NSSound.beep()
            return
        }
        guard !CaptureHotkey.isReserved(hotkey) else {
            onResult?(nil, "That shortcut is reserved by macOS or Open AppShot.")
            NSSound.beep()
            return
        }
        onResult?(hotkey, nil)
    }

    override func flagsChanged(with event: NSEvent) {
        let deviceOptionFlags = event.modifierFlags.rawValue & 0x00000060
        if deviceOptionFlags == 0x00000060 {
            onResult?(.dualOption, nil)
        }
    }

    private func updateColors() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(granted ? "Allowed" : "Required")
                .font(.caption.weight(.medium))
                .foregroundStyle(granted ? .green : .orange)
            Button("Open Settings", action: openSettings)
                .controlSize(.small)
        }
    }
}
