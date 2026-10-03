import AppKit
import OpenAppShotCore
import Testing

struct CaptureHotkeyTests {
    private func keyDown(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        isARepeat: Bool = false
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: isARepeat,
                keyCode: keyCode
            )
        )
    }

    @Test func rejectsShortcutsWithOneModifier() throws {
        let event = try keyDown(keyCode: 40, characters: "k", modifiers: [.command])
        #expect(CaptureHotkey.keyboard(event: event) == nil)
    }

    @Test func recordsTwoModifierShortcut() throws {
        let event = try keyDown(keyCode: 40, characters: "k", modifiers: [.option, .shift])
        let hotkey = try #require(CaptureHotkey.keyboard(event: event))
        #expect(hotkey.displayName == "⌥⇧K")
        #expect(CaptureHotkey.isAllowed(hotkey))
        #expect(hotkey.matchesKeyDown(event))
    }

    @Test func namesKeysWithoutCharactersByKeyCode() throws {
        let event = try keyDown(keyCode: 105, characters: "", modifiers: [.control, .option])
        let hotkey = try #require(CaptureHotkey.keyboard(event: event))
        #expect(hotkey.displayName == "⌃⌥Key 105")
    }

    @Test func reservesTheInAppCaptureShortcut() throws {
        let event = try keyDown(keyCode: 8, characters: "c", modifiers: [.command, .shift])
        let hotkey = try #require(CaptureHotkey.keyboard(event: event))
        #expect(!CaptureHotkey.isAllowed(hotkey))
    }

    @Test func ignoresAutoRepeat() throws {
        let first = try keyDown(keyCode: 40, characters: "k", modifiers: [.option, .shift])
        let repeated = try keyDown(keyCode: 40, characters: "k", modifiers: [.option, .shift], isARepeat: true)
        let hotkey = try #require(CaptureHotkey.keyboard(event: first))
        #expect(!hotkey.matchesKeyDown(repeated))
    }
}
