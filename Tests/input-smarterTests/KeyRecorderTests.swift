import AppKit
import Carbon
import Foundation
import Testing

@testable import input_smarter

/// The recorder has to capture the key and the modifiers, not the text the
/// key would type.
@Test @MainActor func theRecorderCapturesTheKeyAndTheModifiers() {
    let view = KeyCaptureView()
    var captured: KeyCombo?
    view.onChange = { captured = $0 }

    let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.control, .option],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "c",
        charactersIgnoringModifiers: "c",
        isARepeat: false,
        keyCode: 8
    )
    view.keyDown(with: event!)

    #expect(captured == KeyCombo(keyCode: 8, modifiers: UInt32(controlKey) | UInt32(optionKey)))
}

/// A modifier that is let go does not take the combination away: it is
/// usually released before the key itself.
@Test @MainActor func aReleasedModifierDoesNotClearTheCombination() {
    let view = KeyCaptureView()
    var captured: KeyCombo?
    view.onChange = { captured = $0 }

    let down = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.option],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: " ",
        charactersIgnoringModifiers: " ",
        isARepeat: false,
        keyCode: 49
    )
    view.keyDown(with: down!)

    let released = NSEvent.keyEvent(
        with: .flagsChanged,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: 58
    )
    view.flagsChanged(with: released!)

    #expect(captured == KeyCombo(keyCode: 49, modifiers: UInt32(optionKey)))
}
