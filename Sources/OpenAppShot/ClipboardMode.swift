import Foundation

enum ClipboardMode: String, CaseIterable, Identifiable {
    case imageAndFullContext
    case imageAndReferences
    case imageOnly
    case accessibilityOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .imageAndFullContext: "Image + Full Accessibility"
        case .imageAndReferences: "Image + File References"
        case .imageOnly: "Image Only"
        case .accessibilityOnly: "Accessibility Only"
        }
    }

    var detail: String {
        switch self {
        case .imageAndFullContext:
            "Screenshot, readable text for every captured element, and redacted structured context."
        case .imageAndReferences:
            "Screenshot and local paths to the stored Accessibility files. Best for local agents and TUIs."
        case .imageOnly:
            "Screenshot pixels without Accessibility text or local paths."
        case .accessibilityOnly:
            "Readable and structured Accessibility context without screenshot pixels."
        }
    }

    var includesImage: Bool {
        self != .accessibilityOnly
    }

    var includesFullContext: Bool {
        self == .imageAndFullContext || self == .accessibilityOnly
    }

    var includesFileReferences: Bool {
        self == .imageAndReferences
    }

    var includesStructuredContext: Bool {
        includesFullContext
    }
}
