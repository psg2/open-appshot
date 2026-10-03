import AppKit
import Foundation

public enum CaptureSound: String, CaseIterable, Identifiable {
    case none = ""
    case glass = "Glass"
    case hero = "Hero"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case submarine = "Submarine"
    case tink = "Tink"

    public var id: String { rawValue }
    public var displayName: String { self == .none ? "None" : rawValue }

    public func play() {
        guard self != .none else { return }
        NSSound(named: rawValue)?.play()
    }
}
