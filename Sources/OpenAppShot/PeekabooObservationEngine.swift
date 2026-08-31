import AppKit
import Foundation

final class PeekabooObservationEngine: ObservationEngine {
    let kind: ObservationEngineKind = .peekaboo

    private let fileManager = FileManager.default

    func observe(application: NSRunningApplication, captureDirectory: URL) throws -> ObservationResult {
        let pid = application.processIdentifier
        let appName = application.localizedName ?? application.bundleIdentifier ?? "PID \(pid)"
        let windowListURL = captureDirectory.appendingPathComponent("windows.json")
        let windowListResult = try run(
            arguments: ["window", "list", "--pid", String(pid), "--json", "--no-remote"],
            captureDirectory: captureDirectory,
            stdoutURL: windowListURL,
            stderrName: "windows.stderr.txt"
        )
        guard windowListResult.status == 0 else {
            throw ObservationEngineError.peekabooFailed(commandError("window list", result: windowListResult))
        }

        let windowList = try jsonDictionary(windowListResult.stdout)
        guard (windowList["success"] as? Bool) == true,
            let data = windowList["data"] as? [String: Any],
            let windows = data["windows"] as? [[String: Any]]
        else {
            throw ObservationEngineError.invalidPeekabooResponse(jsonErrorMessage(windowList))
        }
        guard let selected = preferredWindow(in: windows), let windowID = integer(selected["window_id"]) else {
            throw ObservationEngineError.noWindow(appName)
        }

        let windowTitle = string(selected["window_title"]) ?? "Untitled window"
        let screenshotURL = captureDirectory.appendingPathComponent("screenshot.png")
        let combinedURL = captureDirectory.appendingPathComponent("peekaboo-combined.json")
        let combined = try run(
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
            stdoutURL: combinedURL,
            stderrName: "peekaboo-combined.stderr.txt"
        )

        let observationData: [String: Any]
        let strategy: String
        var diagnostics = [windowListURL, combinedURL]
        if combined.status == 0,
            let response = try? jsonDictionary(combined.stdout),
            (response["success"] as? Bool) == true,
            let data = response["data"] as? [String: Any]
        {
            observationData = data
            strategy = "Peekaboo combined screenshot + Accessibility"
        } else {
            let screenshotResponseURL = captureDirectory.appendingPathComponent("peekaboo-screenshot.json")
            let screenshotResult = try run(
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
                stdoutURL: screenshotResponseURL,
                stderrName: "peekaboo-screenshot.stderr.txt"
            )
            guard screenshotResult.status == 0,
                let response = try? jsonDictionary(screenshotResult.stdout),
                (response["success"] as? Bool) == true
            else {
                throw ObservationEngineError.peekabooFailed(commandError("screenshot fallback", result: screenshotResult))
            }

            let accessibilityURL = captureDirectory.appendingPathComponent("peekaboo-accessibility.json")
            let accessibilityResult = try run(
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
                stderrName: "peekaboo-accessibility.stderr.txt"
            )
            guard accessibilityResult.status == 0 else {
                throw ObservationEngineError.peekabooFailed(commandError("Accessibility fallback", result: accessibilityResult))
            }
            let accessibilityResponse = try jsonDictionary(accessibilityResult.stdout)
            guard (accessibilityResponse["success"] as? Bool) == true,
                let data = accessibilityResponse["data"] as? [String: Any]
            else {
                throw ObservationEngineError.invalidPeekabooResponse(jsonErrorMessage(accessibilityResponse))
            }
            observationData = data
            strategy = "Peekaboo split screenshot + Accessibility fallback"
            diagnostics.append(contentsOf: [screenshotResponseURL, accessibilityURL])
        }

        guard fileManager.fileExists(atPath: screenshotURL.path) else {
            throw ObservationEngineError.missingScreenshot
        }

        let elements = (observationData["ui_elements"] as? [[String: Any]] ?? []).enumerated().map {
            observedElement(index: $0.offset, dictionary: $0.element)
        }
        return ObservationResult(
            engine: kind,
            window: ObservedWindow(
                id: windowID,
                title: windowTitle,
                bounds: observedBounds(selected["bounds"]) ?? ObservedBounds(x: 0, y: 0, width: 0, height: 0)
            ),
            elements: elements,
            truncation: observationTruncation(observationData["truncation"]),
            captureStrategy: strategy,
            diagnosticURLs: diagnostics
        )
    }

    private func observedElement(index: Int, dictionary: [String: Any]) -> ObservedElement {
        let role = string(dictionary["ax_role"]) ?? string(dictionary["role"]) ?? "AXUnknown"
        let roleDescription = string(dictionary["role_description"])
        let secure = [role, roleDescription]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("secure") || $0.contains("password") }
        return ObservedElement(
            index: integer(dictionary["index"]) ?? index,
            parentIndex: integer(dictionary["parent_index"]),
            depth: integer(dictionary["depth"]) ?? 0,
            role: role,
            subrole: string(dictionary["subrole"]),
            label: string(dictionary["label"]),
            title: string(dictionary["title"]),
            value: secure ? "[secure value redacted]" : string(dictionary["value"]),
            elementDescription: string(dictionary["description"]) ?? roleDescription,
            help: string(dictionary["help"]),
            bounds: observedBounds(dictionary["bounds"]),
            isActionable: dictionary["is_actionable"] as? Bool ?? false,
            isEnabled: dictionary["is_enabled"] as? Bool,
            isFocused: dictionary["is_focused"] as? Bool,
            actions: dictionary["actions"] as? [String] ?? []
        )
    }

    private func observationTruncation(_ value: Any?) -> ObservationTruncation {
        guard let dictionary = value as? [String: Any] else { return ObservationTruncation() }
        return ObservationTruncation(
            maxDepthReached: bool(dictionary, keys: ["max_depth_reached", "maxDepthReached"]),
            maxElementCountReached: bool(dictionary, keys: ["max_element_count_reached", "maxElementCountReached"]),
            maxChildrenPerNodeReached: bool(dictionary, keys: ["max_children_per_node_reached", "maxChildrenPerNodeReached"]),
            deadlineReached: bool(dictionary, keys: ["deadline_reached", "deadlineReached"]),
            incompleteAccessibilityRead: bool(dictionary, keys: ["incomplete_accessibility_read", "incompleteAccessibilityRead"]),
            reason: string(dictionary["reason"])
        )
    }

    private func bool(_ dictionary: [String: Any], keys: [String]) -> Bool {
        keys.lazy.compactMap { dictionary[$0] as? Bool }.first ?? false
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

    private func observedBounds(_ value: Any?) -> ObservedBounds? {
        guard let bounds = value as? [String: Any] else { return nil }
        return ObservedBounds(
            x: double(bounds["x"]),
            y: double(bounds["y"]),
            width: double(bounds["width"]),
            height: double(bounds["height"])
        )
    }

    private func run(
        arguments: [String],
        captureDirectory: URL,
        stdoutURL: URL,
        stderrName: String
    ) throws -> PeekabooProcessResult {
        guard let executableURL = executableURL() else {
            throw ObservationEngineError.peekabooNotInstalled
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
        return PeekabooProcessResult(
            status: process.terminationStatus,
            stdout: try Data(contentsOf: stdoutURL),
            stderr: try Data(contentsOf: stderrURL)
        )
    }

    private func executableURL() -> URL? {
        let environmentPath = ProcessInfo.processInfo.environment["PEEKABOO_CLI_PATH"]
        return [environmentPath, "/opt/homebrew/bin/peekaboo", "/usr/local/bin/peekaboo"]
            .compactMap { $0 }
            .first(where: { fileManager.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    private func jsonDictionary(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ObservationEngineError.invalidPeekabooResponse("the root JSON value is not an object")
        }
        return object
    }

    private func jsonErrorMessage(_ response: [String: Any]) -> String {
        if let error = response["error"] as? [String: Any] {
            return string(error["message"]) ?? compactJSONString(error)
        }
        return "missing success data"
    }

    private func commandError(_ command: String, result: PeekabooProcessResult) -> String {
        let stdout = String(data: result.stdout, encoding: .utf8) ?? ""
        let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
        let details = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return "Peekaboo \(command) failed with exit \(result.status). \(cleanText(details, maximum: 1_200))"
    }

    private func cleanText(_ value: String, maximum: Int) -> String {
        let oneLine = value.replacingOccurrences(of: "\r", with: " ")
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

private struct PeekabooProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: Data
}
