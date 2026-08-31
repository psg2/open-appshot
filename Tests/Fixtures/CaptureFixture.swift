import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

let application = NSApplication.shared
let delegate = FixtureDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
