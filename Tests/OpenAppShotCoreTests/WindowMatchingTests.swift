import CoreGraphics
import OpenAppShotCore
import Testing

struct WindowMatchingTests {
    private let frame = CGRect(x: 0, y: 0, width: 800, height: 600)

    @Test func matchesOverlappingFrameWithoutTitles() {
        let elsewhere = WindowMatching.Window(title: nil, bounds: CGRect(x: 1000, y: 0, width: 800, height: 600))
        let index = WindowMatching.bestMatch(
            screenWindows: [elsewhere, WindowMatching.Window(title: nil, bounds: frame)],
            accessibilityWindow: WindowMatching.Window(title: "Inbox", bounds: frame.offsetBy(dx: 4, dy: 0))
        )
        #expect(index == 1)
    }

    @Test func acceptsPartialOverlapOnlyWhenTitlesAgree() {
        // Overlap of 0.6: below the geometry-only threshold, above the threshold with a title match.
        let moved = CGRect(x: 0, y: 0, width: 100, height: 100)
        let screen = CGRect(x: 0, y: 25, width: 100, height: 100)

        let titled = WindowMatching.bestMatch(
            accessibilityWindows: [WindowMatching.Window(title: "Editor", bounds: moved)],
            screenWindow: WindowMatching.Window(title: "Editor", bounds: screen)
        )
        let untitled = WindowMatching.bestMatch(
            accessibilityWindows: [WindowMatching.Window(title: "Other", bounds: moved)],
            screenWindow: WindowMatching.Window(title: "Editor", bounds: screen)
        )
        #expect(titled == 0)
        #expect(untitled == nil)
    }

    @Test func refusesToChooseBetweenIndistinguishableWindows() {
        let twin = WindowMatching.Window(title: "Document", bounds: frame)
        let index = WindowMatching.bestMatch(screenWindows: [twin, twin], accessibilityWindow: twin)
        #expect(index == nil)
    }

    @Test func focusSeparatesStackedAccessibilityWindows() {
        let index = WindowMatching.bestMatch(
            accessibilityWindows: [
                WindowMatching.Window(title: "Document", bounds: frame),
                WindowMatching.Window(title: "Document", bounds: frame, isFocused: true),
            ],
            screenWindow: WindowMatching.Window(title: "Document", bounds: frame)
        )
        #expect(index == 1)
    }

    @Test func ignoresEmptyAndDisjointFrames() {
        let index = WindowMatching.bestMatch(
            screenWindows: [
                WindowMatching.Window(title: "Document", bounds: .zero),
                WindowMatching.Window(title: "Document", bounds: CGRect(x: 2000, y: 2000, width: 800, height: 600)),
            ],
            accessibilityWindow: WindowMatching.Window(title: "Document", bounds: frame)
        )
        #expect(index == nil)
    }
}
