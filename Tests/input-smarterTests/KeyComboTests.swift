import AppKit
import Carbon
import Foundation
import Testing

@testable import input_smarter

/// The combination is shown to the user in the menu and in the settings
/// window, so the modifiers have to come in the order macOS uses them.
@Test func aKeyComboShowsTheModifiersInTheUsualOrder() {
    let combo = KeyCombo(
        keyCode: 49,
        modifiers: UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
    )
    #expect(combo.display == "⌃⌥⌘空格")
}

/// A key without modifiers is just the key.
@Test func aKeyComboWithoutModifiersIsOnlyTheKey() {
    #expect(KeyCombo(keyCode: 49, modifiers: 0).display == "空格")
}

/// The flags of an event have to become the mask Carbon expects.
@Test func theModifierFlagsOfAnEventBecomeTheCarbonMask() {
    let flags: NSEvent.ModifierFlags = [.command, .shift]
    #expect(KeyCombo.carbonModifiers(from: flags) == UInt32(cmdKey) | UInt32(shiftKey))
}

/// The caps lock is a state, not a modifier: it must not end up in the mask.
@Test func theCapsLockIsNotAModifier() {
    #expect(KeyCombo.carbonModifiers(from: [.capsLock]) == 0)
}
