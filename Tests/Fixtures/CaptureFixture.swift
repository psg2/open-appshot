import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private let runsInBackground = CommandLine.arguments.contains("--background")
    private let activatesForHotkey = CommandLine.arguments.contains("--activate-for-hotkey")
    private let createsWindow = !CommandLine.arguments.contains("--no-window")
    private let createsAmbiguousWindows = CommandLine.arguments.contains("--ambiguous-windows")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard createsWindow else { return }
        let window = makeWindow()
        window.center()
        present(window)
        windows.append(window)

        if createsAmbiguousWindows {
            let duplicate = makeWindow()
            duplicate.setFrameOrigin(window.frame.origin)
            duplicate.orderBack(nil)
            windows.append(duplicate)
        }
    }

    private func makeWindow() -> NSWindow {
        let label = NSTextField(labelWithString: "Observable Accessibility content")
        label.font = .systemFont(ofSize: 18, weight: .medium)

        let button = NSButton(title: "Fixture button", target: nil, action: nil)
        button.bezelStyle = .rounded

        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Open AppShot Capture Fixture"
        window.contentView = stack
        return window
    }

    private func present(_ window: NSWindow) {
        if runsInBackground {
            window.orderBack(nil)
            if activatesForHotkey {
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

let application = NSApplication.shared
let delegate = FixtureDelegate()
application.delegate = delegate
application.setActivationPolicy(CommandLine.arguments.contains("--background") ? .accessory : .regular)
application.run()
