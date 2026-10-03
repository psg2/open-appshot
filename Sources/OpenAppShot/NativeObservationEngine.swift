import AppKit
import ApplicationServices
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

final class NativeObservationEngine {
    private let fileManager = FileManager.default
    private let contentTimeout: DispatchTimeInterval = .seconds(5)
    private let screenshotTimeout: DispatchTimeInterval = .seconds(5)

    func observe(application: NSRunningApplication, captureDirectory: URL) throws -> ObservationResult {
        _ = NSApplication.shared
        let appName = application.localizedName ?? application.bundleIdentifier ?? "PID \(application.processIdentifier)"
        let accessibilityWindows = AXWindowReader.windows(for: application.processIdentifier)
        let content = try shareableContent()
        let candidates = content.windows.filter {
            $0.owningApplication?.processID == application.processIdentifier
                && $0.windowLayer == 0
                && $0.frame.width >= 50
                && $0.frame.height >= 50
        }
        let window = try preferredWindow(
            in: candidates,
            accessibilityWindows: accessibilityWindows,
            appName: appName
        )

        let screenshotURL = captureDirectory.appendingPathComponent("screenshot.png")
        let image = try capture(window: window)
        try writePNG(image, to: screenshotURL)

        let selectedAXWindow = preferredAccessibilityWindow(for: window, in: accessibilityWindows)
        let collection: NativeAXCollection
        if let selectedAXWindow {
            collection = NativeAXTreeCollector().collect(from: selectedAXWindow.element)
        } else {
            collection = NativeAXCollection(
                elements: [],
                truncation: ObservationTruncation(
                    incompleteAccessibilityRead: true,
                    reason: "No Accessibility window confidently matched the captured ScreenCaptureKit window."
                )
            )
        }

        let inventoryURL = captureDirectory.appendingPathComponent("windows.json")
        try writeInventory(candidateCount: candidates.count, selected: window, to: inventoryURL)

        return ObservationResult(
            window: ObservedWindow(
                id: Int(window.windowID),
                title: window.title.nonEmpty ?? selectedAXWindow?.title.nonEmpty ?? "Untitled window",
                bounds: ObservedBounds(window.frame)
            ),
            elements: collection.elements,
            truncation: collection.truncation,
            captureStrategy: "native ScreenCaptureKit + Accessibility",
            diagnosticURLs: [inventoryURL]
        )
    }

    private func shareableContent() throws -> SCShareableContent {
        let semaphore = DispatchSemaphore(value: 0)
        let box = CallbackResultBox<SCShareableContent>()
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            if let content {
                box.store(.success(content))
            } else {
                box.store(.failure(error ?? ObservationEngineError.screenCaptureFailed("ScreenCaptureKit returned no content.")))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + contentTimeout) == .success else {
            throw ObservationEngineError.screenCaptureTimedOut
        }
        return try box.value()
    }

    private func capture(window: SCWindow) throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        let expectedWidth = max(Int(filter.contentRect.width * scale), 1)
        let expectedHeight = max(Int(filter.contentRect.height * scale), 1)
        configuration.width = expectedWidth
        configuration.height = expectedHeight
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.scalesToFit = true
        configuration.includeChildWindows = false

        let semaphore = DispatchSemaphore(value: 0)
        let box = CallbackResultBox<CGImage>()
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
            if let image {
                box.store(.success(image))
            } else {
                box.store(.failure(error ?? ObservationEngineError.missingScreenshot))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + screenshotTimeout) == .success else {
            throw ObservationEngineError.screenCaptureTimedOut
        }
        let image = try box.value()
        guard image.width == expectedWidth, image.height == expectedHeight else {
            throw ObservationEngineError.screenCaptureFailed(
                "ScreenCaptureKit returned \(image.width)x\(image.height) for an expected \(expectedWidth)x\(expectedHeight) window."
            )
        }
        return image
    }

    private func preferredWindow(
        in windows: [SCWindow],
        accessibilityWindows: [AXWindowDescriptor],
        appName: String
    ) throws -> SCWindow {
        guard !windows.isEmpty else { throw ObservationEngineError.noWindow(appName) }
        if windows.count == 1 { return windows[0] }

        let focused = accessibilityWindows.first(where: \.isFocused)
        if let focused {
            let ranked =
                windows
                .map { ($0, screenWindowConfidence($0, accessibilityWindow: focused)) }
                .filter(\.1.isQualified)
                .sorted { $0.1.score > $1.1.score }
            if let best = ranked.first, isUnambiguous(best: best.1, second: ranked.dropFirst().first?.1) {
                return best.0
            }
        }

        let active = windows.filter(\.isActive)
        guard active.count == 1 else { throw ObservationEngineError.ambiguousWindow(appName) }
        return active[0]
    }

    private func preferredAccessibilityWindow(for window: SCWindow, in windows: [AXWindowDescriptor]) -> AXWindowDescriptor? {
        let ranked =
            windows
            .map { ($0, accessibilityWindowConfidence($0, screenWindow: window)) }
            .filter(\.1.isQualified)
            .sorted { $0.1.score > $1.1.score }
        guard let best = ranked.first,
            isUnambiguous(best: best.1, second: ranked.dropFirst().first?.1)
        else { return nil }
        return best.0
    }

    private func screenWindowConfidence(
        _ window: SCWindow,
        accessibilityWindow: AXWindowDescriptor
    ) -> WindowMatchConfidence {
        windowMatchConfidence(
            screenTitle: window.title,
            screenBounds: window.frame,
            accessibilityWindow: accessibilityWindow
        )
    }

    private func accessibilityWindowConfidence(
        _ descriptor: AXWindowDescriptor,
        screenWindow: SCWindow
    ) -> WindowMatchConfidence {
        windowMatchConfidence(
            screenTitle: screenWindow.title,
            screenBounds: screenWindow.frame,
            accessibilityWindow: descriptor
        )
    }

    private func windowMatchConfidence(
        screenTitle: String?,
        screenBounds: CGRect,
        accessibilityWindow: AXWindowDescriptor
    ) -> WindowMatchConfidence {
        let geometry = rectangleSimilarity(screenBounds, accessibilityWindow.bounds)
        let titleMatches = screenTitle?.nonEmpty.map { accessibilityWindow.title == $0 } ?? false
        let isQualified = geometry >= 0.80 || (titleMatches && geometry >= 0.50)
        let score = geometry + (titleMatches ? 1.0 : 0) + (accessibilityWindow.isFocused ? 0.25 : 0)
        return WindowMatchConfidence(score: score, isQualified: isQualified)
    }

    private func isUnambiguous(
        best: WindowMatchConfidence,
        second: WindowMatchConfidence?
    ) -> Bool {
        guard best.isQualified else { return false }
        guard let second else { return true }
        return best.score - second.score >= 0.15
    }

    private func rectangleSimilarity(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else { return 0 }
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ObservationEngineError.missingScreenshot
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ObservationEngineError.missingScreenshot
        }
    }

    private func writeInventory(candidateCount: Int, selected: SCWindow, to url: URL) throws {
        let inventory = NativeWindowInventory(
            engine: "native",
            selectedWindowID: Int(selected.windowID),
            candidateWindowCount: candidateCount,
            selectedWindow: NativeWindowInventory.Item(
                id: Int(selected.windowID),
                title: selected.title,
                bounds: ObservedBounds(selected.frame),
                isActive: selected.isActive,
                isOnScreen: selected.isOnScreen
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(inventory).write(to: url, options: .atomic)
    }
}

private struct WindowMatchConfidence {
    let score: Double
    let isQualified: Bool
}

private final class CallbackResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.withLock {
            self.result = result
        }
    }

    func value() throws -> Value {
        try lock.withLock {
            guard let result else {
                throw ObservationEngineError.screenCaptureFailed("The capture callback did not return a result.")
            }
            return try result.get()
        }
    }
}

private struct NativeWindowInventory: Codable {
    let engine: String
    let selectedWindowID: Int
    let candidateWindowCount: Int
    let selectedWindow: Item

    struct Item: Codable {
        let id: Int
        let title: String?
        let bounds: ObservedBounds
        let isActive: Bool
        let isOnScreen: Bool
    }
}

private struct AXWindowDescriptor {
    let element: AXUIElement
    let title: String
    let bounds: CGRect
    let isFocused: Bool
}

private enum AXWindowReader {
    static func windows(for processIdentifier: pid_t) -> [AXWindowDescriptor] {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.2)
        let focused = AXReader.elementAttribute(application, kAXFocusedWindowAttribute as String)
        let windows = AXReader.elementArrayAttribute(application, kAXWindowsAttribute as String)
        return windows.map { window in
            AXUIElementSetMessagingTimeout(window, 0.2)
            return AXWindowDescriptor(
                element: window,
                title: AXReader.stringAttribute(window, kAXTitleAttribute as String) ?? "",
                bounds: AXReader.bounds(of: window) ?? .zero,
                isFocused: focused.map { CFEqual($0, window) } ?? false
            )
        }
    }
}

private struct NativeAXCollection {
    let elements: [ObservedElement]
    let truncation: ObservationTruncation
}

// CFHash alone is not identity: two distinct elements may collide, so equality must go through CFEqual.
private struct AXElementIdentity: Hashable {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    static func == (lhs: AXElementIdentity, rhs: AXElementIdentity) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

private final class NativeAXTreeCollector {
    private let maxDepth = 20
    private let maxElements = 1_500
    private let maxChildrenPerNode = 500
    private let deadlineInterval: TimeInterval = 4
    private let childAttributes = [
        kAXChildrenAttribute as String,
        "AXNavigationOrder",
        "AXVisibleChildren",
        kAXRowsAttribute as String,
        "AXWebAreaChildren",
    ]

    func collect(from root: AXUIElement) -> NativeAXCollection {
        let deadline = Date().addingTimeInterval(deadlineInterval)
        var truncation = ObservationTruncation()
        var elements: [ObservedElement] = []
        var seen: Set<AXElementIdentity> = []
        var stack: [(element: AXUIElement, depth: Int, parentIndex: Int?)] = [(root, 0, nil)]

        while let current = stack.popLast() {
            if Date() >= deadline {
                truncation.deadlineReached = true
                truncation.reason = "Accessibility traversal exceeded \(Int(deadlineInterval)) seconds."
                break
            }
            if elements.count >= maxElements {
                truncation.maxElementCountReached = true
                truncation.reason = "Accessibility traversal reached \(maxElements) elements."
                break
            }

            guard seen.insert(AXElementIdentity(current.element)).inserted else { continue }
            AXUIElementSetMessagingTimeout(current.element, 0.2)

            let index = elements.count
            elements.append(observedElement(current.element, index: index, parentIndex: current.parentIndex, depth: current.depth))

            guard current.depth < maxDepth else {
                if !children(of: current.element).isEmpty { truncation.maxDepthReached = true }
                continue
            }

            var children = children(of: current.element)
            if children.count > maxChildrenPerNode {
                children = Array(children.prefix(maxChildrenPerNode))
                truncation.maxChildrenPerNodeReached = true
            }
            for child in children.reversed() {
                stack.append((child, current.depth + 1, index))
            }
        }

        return NativeAXCollection(elements: elements, truncation: truncation)
    }

    private func observedElement(_ element: AXUIElement, index: Int, parentIndex: Int?, depth: Int) -> ObservedElement {
        let role = AXReader.stringAttribute(element, kAXRoleAttribute as String) ?? "AXUnknown"
        let subrole = AXReader.stringAttribute(element, kAXSubroleAttribute as String)
        let roleDescription = AXReader.stringAttribute(element, "AXRoleDescription")
        let description = AXReader.stringAttribute(element, kAXDescriptionAttribute as String)
        let secure = [role, subrole, roleDescription, description]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("secure") || $0.contains("password") }
        let actions = AXReader.actionNames(element)
        let knownActionableRoles = ["AXButton", "AXLink", "AXMenuItem", "AXCheckBox", "AXRadioButton", "AXPopUpButton"]

        return ObservedElement(
            index: index,
            parentIndex: parentIndex,
            depth: depth,
            role: role,
            subrole: subrole,
            label: AXReader.stringAttribute(element, "AXLabel"),
            title: AXReader.stringAttribute(element, kAXTitleAttribute as String),
            value: secure ? "[secure value redacted]" : AXReader.stringAttribute(element, kAXValueAttribute as String),
            elementDescription: description ?? roleDescription,
            help: AXReader.stringAttribute(element, kAXHelpAttribute as String),
            bounds: AXReader.bounds(of: element).map(ObservedBounds.init),
            isSecure: secure,
            isActionable: !actions.isEmpty || knownActionableRoles.contains(role),
            isEnabled: AXReader.boolAttribute(element, kAXEnabledAttribute as String),
            isFocused: AXReader.boolAttribute(element, kAXFocusedAttribute as String),
            actions: actions
        )
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var children: [AXUIElement] = []
        var seen: Set<AXElementIdentity> = []
        for attribute in childAttributes {
            for child in AXReader.elementArrayAttribute(element, attribute) {
                if seen.insert(AXElementIdentity(child)).inserted {
                    children.append(child)
                }
            }
        }
        return children
    }
}

private enum AXReader {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        if let string = value(element, attribute) as? String {
            return string.nonEmpty
        }
        if let number = value(element, attribute) as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (value(element, attribute) as? NSNumber)?.boolValue
    }

    static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func elementArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }

    static func bounds(of element: AXUIElement) -> CGRect? {
        guard let position = pointAttribute(element, kAXPositionAttribute as String),
            let size = sizeAttribute(element, kAXSizeAttribute as String)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    private static func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
