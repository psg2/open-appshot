import Foundation

public struct ObservationResult {
    public let window: ObservedWindow
    public let elements: [ObservedElement]
    public let truncation: ObservationTruncation
    public let captureStrategy: String
    public let diagnosticURLs: [URL]

    public func accessibilityJSON() throws -> Data {
        let document = AccessibilityDocument(
            success: true,
            data: AccessibilityPayload(
                engine: "native",
                windowID: window.id,
                windowTitle: window.title,
                elementCount: elements.count,
                uiElements: elements,
                truncation: truncation
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }
}

public struct ObservedWindow: Codable {
    public let id: Int
    public let title: String
    public let bounds: ObservedBounds
}

public struct ObservedBounds: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(_ rectangle: CGRect) {
        x = rectangle.origin.x
        y = rectangle.origin.y
        width = rectangle.size.width
        height = rectangle.size.height
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var rectangle: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public struct ObservedElement: Codable {
    public let index: Int
    public let parentIndex: Int?
    public let depth: Int
    public let role: String
    public let subrole: String?
    public let label: String?
    public let title: String?
    public let value: String?
    public let elementDescription: String?
    public let help: String?
    public let bounds: ObservedBounds?
    public let isSecure: Bool
    public let isActionable: Bool
    public let isEnabled: Bool?
    public let isFocused: Bool?
    public let actions: [String]

    public enum CodingKeys: String, CodingKey {
        case index
        case parentIndex = "parent_index"
        case depth
        case role
        case subrole
        case label
        case title
        case value
        case elementDescription = "description"
        case help
        case bounds
        case isSecure = "is_secure"
        case isActionable = "is_actionable"
        case isEnabled = "is_enabled"
        case isFocused = "is_focused"
        case actions
    }
}

public struct ObservationTruncation: Codable {
    public var maxDepthReached = false
    public var maxElementCountReached = false
    public var maxChildrenPerNodeReached = false
    public var deadlineReached = false
    public var incompleteAccessibilityRead = false
    public var reason: String?

    public init(
        maxDepthReached: Bool = false,
        maxElementCountReached: Bool = false,
        maxChildrenPerNodeReached: Bool = false,
        deadlineReached: Bool = false,
        incompleteAccessibilityRead: Bool = false,
        reason: String? = nil
    ) {
        self.maxDepthReached = maxDepthReached
        self.maxElementCountReached = maxElementCountReached
        self.maxChildrenPerNodeReached = maxChildrenPerNodeReached
        self.deadlineReached = deadlineReached
        self.incompleteAccessibilityRead = incompleteAccessibilityRead
        self.reason = reason
    }

    public enum CodingKeys: String, CodingKey {
        case maxDepthReached = "max_depth_reached"
        case maxElementCountReached = "max_element_count_reached"
        case maxChildrenPerNodeReached = "max_children_per_node_reached"
        case deadlineReached = "deadline_reached"
        case incompleteAccessibilityRead = "incomplete_accessibility_read"
        case reason
    }

    public var isIncomplete: Bool {
        maxDepthReached || maxElementCountReached || maxChildrenPerNodeReached || deadlineReached || incompleteAccessibilityRead
    }
}

private struct AccessibilityDocument: Codable {
    let success: Bool
    let data: AccessibilityPayload
}

private struct AccessibilityPayload: Codable {
    let engine: String
    let windowID: Int
    let windowTitle: String
    let elementCount: Int
    let uiElements: [ObservedElement]
    let truncation: ObservationTruncation

    enum CodingKeys: String, CodingKey {
        case engine
        case windowID = "window_id"
        case windowTitle = "window_title"
        case elementCount = "element_count"
        case uiElements = "ui_elements"
        case truncation
    }
}

public enum ObservationEngineError: LocalizedError {
    case noWindow(String)
    case ambiguousWindow(String)
    case screenCaptureTimedOut
    case screenCaptureFailed(String)
    case missingScreenshot

    public var errorDescription: String? {
        switch self {
        case .noWindow(let appName):
            return "No capturable window was found for \(appName)."
        case .ambiguousWindow(let appName):
            return "Open AppShot could not identify one active window for \(appName). Bring the intended window forward and try again."
        case .screenCaptureTimedOut:
            return "Native macOS window capture timed out."
        case .screenCaptureFailed(let message):
            return "Native macOS window capture failed: \(message)"
        case .missingScreenshot:
            return "The observation engine completed without producing a screenshot."
        }
    }
}
