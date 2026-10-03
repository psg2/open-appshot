import AppKit

runCommandLineCommand(CommandLine.arguments)

private let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.run()
