import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)
let leftOption: CGKeyCode = 58
let rightOption: CGKeyCode = 61

func post(_ keyCode: CGKeyCode, down: Bool, flags: UInt64) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else {
        exit(EXIT_FAILURE)
    }
    event.flags = CGEventFlags(rawValue: flags)
    event.post(tap: .cghidEventTap)
}

post(leftOption, down: true, flags: 0x00080020)
usleep(80_000)
post(rightOption, down: true, flags: 0x00080060)
usleep(120_000)
post(rightOption, down: false, flags: 0x00080020)
usleep(80_000)
post(leftOption, down: false, flags: 0)
