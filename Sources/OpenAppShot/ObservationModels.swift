import Foundation

struct ObservationResult {
    let window: ObservedWindow
    let elements: [ObservedElement]
    let truncation: ObservationTruncation
    let captureStrategy: String
    let diagnosticURLs: [URL]

    func accessibilityJSON() throws -> Data {
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

struct ObservedWindow: Codable {
    let id: Int
    let title: String
    let bounds: ObservedBounds
}

struct ObservedBounds: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rectangle: CGRect) {
        x = rectangle.origin.x
        y = rectangle.origin.y
        width = rectangle.size.width
        height = rectangle.size.height
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var rectangle: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct ObservedElement: Codable {
    let index: Int
    let parentIndex: Int?
    let depth: Int
    let role: String
    let subrole: String?
    let label: String?
    let title: String?
    let value: String?
    let elementDescription: String?
    let help: String?
    let bounds: ObservedBounds?
    let isSecure: Bool
    let isActionable: Bool
    let isEnabled: Bool?
    let isFocused: Bool?
    let actions: [String]

    enum CodingKeys: String, CodingKey {
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

struct ObservationTruncation: Codable {
    var maxDepthReached = false
    var maxElementCountReached = false
    var maxChildrenPerNodeReached = false
    var deadlineReached = false
    var incompleteAccessibilityRead = false
    var reason: String?

    init(
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

    enum CodingKeys: String, CodingKey {
        case maxDepthReached = "max_depth_reached"
        case maxElementCountReached = "max_element_count_reached"
        case maxChildrenPerNodeReached = "max_children_per_node_reached"
        case deadlineReached = "deadline_reached"
        case incompleteAccessibilityRead = "incomplete_accessibility_read"
        case reason
    }

    var isIncomplete: Bool {
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

enum ObservationEngineError: LocalizedError {
    case noWindow(String)
    case ambiguousWindow(String)
    case screenCaptureTimedOut
    case screenCaptureFailed(String)
    case missingScreenshot

    var errorDescription: String? {
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
