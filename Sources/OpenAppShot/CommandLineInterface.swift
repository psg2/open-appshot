import AppKit
import ApplicationServices
import Foundation
import ImageIO
import OpenAppShotCore
import UniformTypeIdentifiers

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

/// Runs a command-line command and exits when the arguments request one; returns otherwise so the app can launch.
func runCommandLineCommand(_ arguments: [String]) {
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

    if arguments.contains("--prune-captures") {
        do {
            guard let rootPath = argumentValue(after: "--storage-root", in: arguments),
                let retentionValue = argumentValue(after: "--retention-days", in: arguments),
                let retentionDays = Int(retentionValue),
                retentionDays >= 0
            else {
                throw AppShotError.invalidArguments(
                    "--prune-captures requires --storage-root <path> and --retention-days <non-negative integer>"
                )
            }
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            let removed = try CaptureStorage.removeExpiredCaptures(at: root, retentionDays: retentionDays)
            print("removed=\(removed.count)")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("error=\(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    if let capturePath = argumentValue(after: "--capture-ownership", in: arguments) {
        let directory = URL(fileURLWithPath: capturePath, isDirectory: true)
        let canDelete =
            CaptureStorage.hasOwnershipMarker(directory)
            || CaptureStorage.hasVerifiedLegacyLayout(directory)
        print("can_delete=\(canDelete)")
        exit(EXIT_SUCCESS)
    }

    if let rootPath = argumentValue(after: "--purge-capture-root", in: arguments) {
        do {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            let removed = try CaptureStorage.purgeOwnedCaptures(at: root)
            print("removed=\(removed.count)")
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

    if arguments.contains("--known-capture-roots-nul") {
        let output = CapturePreferences.knownCaptureRootURLs
            .map { Data($0.path.utf8) + Data([0]) }
            .reduce(into: Data()) { $0.append($1) }
        FileHandle.standardOutput.write(output)
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
}
