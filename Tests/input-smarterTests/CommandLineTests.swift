import Foundation
import Testing

@testable import input_smarter

/// The on/off argument of `--launch-at-login`.
///
/// "ON" used to be read as "off", which silently removed the login item.
@Test func launchAtLoginArgumentIsCaseInsensitive() {
    #expect(CLI.parseToggle("on"))
    #expect(CLI.parseToggle("ON"))
    #expect(CLI.parseToggle("On"))
    #expect(CLI.parseToggle("1"))
    #expect(CLI.parseToggle("yes"))

    #expect(!CLI.parseToggle("off"))
    #expect(!CLI.parseToggle("OFF"))
    #expect(!CLI.parseToggle("Off"))
    #expect(!CLI.parseToggle("0"))
    #expect(!CLI.parseToggle("no"))
}

/// Carbon allows only one hotkey per key and modifier combination.
@Test func hotkeysWithTheSameKeyAndModifiersConflict() {
    let first = HotkeyBinding(id: UUID(), keyCode: 40, modifiers: 6400, inputSourceIDs: ["a"])
    let second = HotkeyBinding(id: UUID(), keyCode: 41, modifiers: 6400, inputSourceIDs: ["b"])
    let third = HotkeyBinding(id: UUID(), keyCode: 40, modifiers: 6400, inputSourceIDs: ["c"])

    #expect(HotkeyManager.conflicts(with: third, in: [first, second]).count == 1)
    #expect(HotkeyManager.conflicts(with: second, in: [first, second]).isEmpty)
    // A binding does not conflict with itself.
    #expect(HotkeyManager.conflicts(with: first, in: [first]).isEmpty)
}

/// The modifier names accepted on the command line.
@Test func modifierNamesAreParsed() {
    #expect(ModifierKey.parse("option") == .leftOption)
    #expect(ModifierKey.parse("OPTION") == .leftOption)
    #expect(ModifierKey.parse("rightOption") == .rightOption)
    #expect(ModifierKey.parse("cmd") == .leftCommand)
    #expect(ModifierKey.parse("nonsense") == nil)
}

/// Without a running app there is no window to open, and the command has to
/// say so instead of doing nothing.
@Test func openingTheSettingsWindowNeedsARunningApp() {
    #expect(SettingsRequest.open(isRunning: false) == false)
}
