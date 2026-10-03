import AppKit
import Foundation

public struct CaptureHotkey: Codable, Equatable {
    public enum Kind: String, Codable {
        case dualOption
        case keyboard
    }

    public let kind: Kind
    public let keyCode: UInt16?
    public let modifierRawValue: UInt
    public let keyDisplay: String?

    public static let dualOption = CaptureHotkey(
        kind: .dualOption,
        keyCode: nil,
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        keyDisplay: nil
    )

    public static let supportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    public var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue).intersection(Self.supportedModifiers)
    }

    public var displayName: String {
        if kind == .dualOption { return "Left ⌥ + Right ⌥" }
        return modifierSymbols + (keyDisplay ?? "Key")
    }

    public var compactDisplayName: String {
        if kind == .dualOption { return "L⌥ + R⌥" }
        return displayName
    }

    public func matchesKeyDown(_ event: NSEvent) -> Bool {
        guard kind == .keyboard, let keyCode else { return false }
        let eventModifiers = event.modifierFlags.intersection(Self.supportedModifiers)
        return event.keyCode == keyCode && eventModifiers == modifiers && !event.isARepeat
    }

    public static func keyboard(event: NSEvent) -> CaptureHotkey? {
        let modifiers = event.modifierFlags.intersection(supportedModifiers)
        guard isAllowedModifierCombination(modifiers) else { return nil }

        return CaptureHotkey(
            kind: .keyboard,
            keyCode: event.keyCode,
            modifierRawValue: modifiers.rawValue,
            keyDisplay: displayKey(for: event)
        )
    }

    public static func isReserved(_ hotkey: CaptureHotkey) -> Bool {
        guard hotkey.kind == .keyboard,
            let keyCode = hotkey.keyCode
        else { return false }

        switch hotkey.modifiers {
        case [.command]:
            return [0, 4, 8, 12, 13, 15, 43, 46].contains(keyCode)
        case [.command, .shift]:
            return [8, 15].contains(keyCode)
        case [.command, .option]:
            return [8, 17, 34].contains(keyCode)
        default:
            return false
        }
    }

    public static func isAllowed(_ hotkey: CaptureHotkey) -> Bool {
        hotkey.kind == .dualOption
            || (hotkey.kind == .keyboard && hotkey.keyCode != nil
                && isAllowedModifierCombination(hotkey.modifiers) && !isReserved(hotkey))
    }

    private static func isAllowedModifierCombination(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        let flags: [NSEvent.ModifierFlags] = [.command, .option, .control, .shift]
        let modifierCount = flags.filter { modifiers.contains($0) }.count
        let includesPrimaryModifier = !modifiers.intersection([.command, .option, .control]).isEmpty
        return modifierCount >= 2 && includesPrimaryModifier
    }

    private var modifierSymbols: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result
    }

    private static func displayKey(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 115: return "Home"
        case 116: return "Page Up"
        case 117: return "Forward Delete"
        case 119: return "End"
        case 121: return "Page Down"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
            return characters?.isEmpty == false ? characters!.uppercased() : "Key \(event.keyCode)"
        }
    }
}
