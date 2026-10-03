import CoreGraphics

/// Pairs ScreenCaptureKit windows with Accessibility windows by geometry and title.
/// A match must be qualified and clearly ahead of the runner-up; otherwise there is no match.
public enum WindowMatching {
    public struct Window {
        public let title: String?
        public let bounds: CGRect
        public let isFocused: Bool

        public init(title: String?, bounds: CGRect, isFocused: Bool = false) {
            self.title = title
            self.bounds = bounds
            self.isFocused = isFocused
        }
    }

    /// The index of the screen window that matches `accessibilityWindow`, or nil when none matches unambiguously.
    public static func bestMatch(screenWindows: [Window], accessibilityWindow: Window) -> Int? {
        unambiguousBest(screenWindows.map { confidence(screen: $0, accessibility: accessibilityWindow) })
    }

    /// The index of the Accessibility window that matches `screenWindow`, or nil when none matches unambiguously.
    public static func bestMatch(accessibilityWindows: [Window], screenWindow: Window) -> Int? {
        unambiguousBest(accessibilityWindows.map { confidence(screen: screenWindow, accessibility: $0) })
    }

    private struct Confidence {
        let score: Double
        let isQualified: Bool
    }

    private static func confidence(screen: Window, accessibility: Window) -> Confidence {
        let geometry = rectangleSimilarity(screen.bounds, accessibility.bounds)
        let titleMatches = screen.title.map { !$0.isEmpty && accessibility.title == $0 } ?? false
        let isQualified = geometry >= 0.80 || (titleMatches && geometry >= 0.50)
        let score = geometry + (titleMatches ? 1.0 : 0) + (accessibility.isFocused ? 0.25 : 0)
        return Confidence(score: score, isQualified: isQualified)
    }

    private static func unambiguousBest(_ confidences: [Confidence]) -> Int? {
        let ranked =
            confidences.enumerated()
            .filter(\.element.isQualified)
            .sorted { $0.element.score > $1.element.score }
        guard let best = ranked.first else { return nil }
        if let second = ranked.dropFirst().first, best.element.score - second.element.score < 0.15 {
            return nil
        }
        return best.offset
    }

    private static func rectangleSimilarity(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else { return 0 }
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}
