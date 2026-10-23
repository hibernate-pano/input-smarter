import AppKit
import Foundation
import Testing

@testable import input_smarter

/// The modifier tap state machine.
///
/// The events are hand-built rather than synthesized through the window
/// server: a posted key event cannot make the system update the real
/// modifier state, so `flagsChanged` events would never report the modifier
/// as down. Hand-built events exercise the same code path the monitors use.
private func flagsChanged(
    key: ModifierKey,
    down: Bool,
    at timestamp: TimeInterval,
    otherModifiers: NSEvent.ModifierFlags = []
) -> NSEvent {
    var flags = otherModifiers
    if down { flags.insert(key.flag) }
    return NSEvent.keyEvent(
        with: .flagsChanged,
        location: .zero,
        modifierFlags: flags,
        timestamp: timestamp,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: key.keyCode
    )!
}

private func keyDown(_ keyCode: UInt16, at timestamp: TimeInterval) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: timestamp,
        windowNumber: 0,
        context: nil,
        characters: "a",
        charactersIgnoringModifiers: "a",
        isARepeat: false,
        keyCode: keyCode
    )!
}

private func makeManager(
    _ bindings: [SingleModifierBinding]
) -> (SingleModifierManager, () -> [String]) {
    let manager = SingleModifierManager()
    manager.sync(bindings)
    var fired: [String] = []
    manager.onTrigger = { fired.append($0.modifier.rawValue) }
    return (manager, { fired })
}

@Test func quickTapFires() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.2))

    #expect(fired() == ["leftOption"])
}

@Test func longHoldDoesNotFire() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100))
    // 0.8s is the limit; 1.0s is clearly too long.
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 101.0))

    #expect(fired().isEmpty)
}

@Test func leftAndRightOptionAreDistinct() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, inputSourceID: "com.apple.keylayout.ABC")
    ])

    // The right key must not trigger a binding on the left key.
    manager.handle(flagsChanged(key: .rightOption, down: true, at: 100))
    manager.handle(flagsChanged(key: .rightOption, down: false, at: 100.1))

    #expect(fired().isEmpty)
}

/// Holding both shifts is a combination, not a tap: the flags still say
/// "shift is down" when one of them is released, so the release can only be
/// read from the key code.
///
/// Both sides are bound here on purpose — with only one of them bound the
/// test cannot see the other side fire.
@Test func holdingBothShiftsIsNotATap() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftShift, inputSourceID: "com.apple.keylayout.ABC"),
        SingleModifierBinding(modifier: .rightShift, inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftShift, down: true, at: 100))
    manager.handle(flagsChanged(key: .rightShift, down: true, at: 100.1, otherModifiers: [.shift]))
    // Left shift released while the right one is still held: the flag stays set.
    manager.handle(flagsChanged(key: .leftShift, down: false, at: 100.2, otherModifiers: [.shift]))
    manager.handle(flagsChanged(key: .rightShift, down: false, at: 100.3, otherModifiers: []))

    #expect(fired().isEmpty)
}

/// The same combination, released in the other order.
@Test func holdingBothShiftsReleasedInTheOtherOrderIsNotATap() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftShift, inputSourceID: "com.apple.keylayout.ABC"),
        SingleModifierBinding(modifier: .rightShift, inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftShift, down: true, at: 100))
    manager.handle(flagsChanged(key: .rightShift, down: true, at: 100.1, otherModifiers: [.shift]))
    manager.handle(flagsChanged(key: .rightShift, down: false, at: 100.2, otherModifiers: [.shift]))
    manager.handle(flagsChanged(key: .leftShift, down: false, at: 100.3, otherModifiers: []))

    #expect(fired().isEmpty)
}

/// Two modifiers of different families are a combination as well.
@Test func holdingTwoDifferentModifiersIsNotATap() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, inputSourceID: "com.apple.keylayout.ABC"),
        SingleModifierBinding(modifier: .leftShift, inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100))
    manager.handle(flagsChanged(key: .leftShift, down: true, at: 100.1, otherModifiers: [.option]))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.2, otherModifiers: [.shift]))
    manager.handle(flagsChanged(key: .leftShift, down: false, at: 100.3, otherModifiers: []))

    #expect(fired().isEmpty)
}

/// The releases that the flags cannot express must not leave stale state
/// behind, or every later tap would be blocked.
@Test func staleStateFromHiddenReleaseDoesNotBlockLaterTaps() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftShift, inputSourceID: "com.apple.keylayout.ABC")
    ])

    // The messy sequence above.
    manager.handle(flagsChanged(key: .leftShift, down: true, at: 100))
    manager.handle(flagsChanged(key: .rightShift, down: true, at: 100.1, otherModifiers: [.shift]))
    manager.handle(flagsChanged(key: .leftShift, down: false, at: 100.2, otherModifiers: [.shift]))
    manager.handle(flagsChanged(key: .rightShift, down: false, at: 100.3, otherModifiers: []))

    // A clean tap afterwards still works.
    manager.handle(flagsChanged(key: .leftShift, down: true, at: 200))
    manager.handle(flagsChanged(key: .leftShift, down: false, at: 200.1))

    #expect(fired() == ["leftShift"])
}

/// A key that was already down when the app started is not a tap: its
/// release must not fire anything.
@Test func releaseOfAnUntrackedKeyDoesNotFire() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100))

    #expect(fired().isEmpty)
}

@Test func doublePressNeedsTwoTapsInTime() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, trigger: .doublePress,
                              inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.1))
    #expect(fired().isEmpty)

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100.2))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.3))
    #expect(fired() == ["leftOption"])
}

/// The modifier's own key press arrives on the key-down monitor too. It must
/// not cancel the pending double press — that press is the second half of the
/// pair.
@Test func theModifiersOwnKeyDownDoesNotCancelTheDoublePress() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, trigger: .doublePress,
                              inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100))
    manager.handleKeyDown(keyDown(ModifierKey.leftOption.keyCode, at: 100.01))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.1))

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100.2))
    manager.handleKeyDown(keyDown(ModifierKey.leftOption.keyCode, at: 100.21))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.3))

    #expect(fired() == ["leftOption"])
}

/// Another key does cancel the pending double press.
@Test func anotherKeyCancelsTheDoublePress() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, trigger: .doublePress,
                              inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.1))
    manager.handleKeyDown(keyDown(0, at: 100.15))

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100.2))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.3))

    #expect(fired().isEmpty)
}

@Test func doublePressTapsTooFarApartDoNotFire() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, trigger: .doublePress,
                              inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.1))
    // 1 second later: outside the 0.35s double press window.
    manager.handle(flagsChanged(key: .leftOption, down: true, at: 101.1))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 101.2))

    #expect(fired().isEmpty)
}

@Test func typingWhileTheModifierIsHeldCancelsTheTap() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftOption, down: true, at: 100))
    // A letter is typed while Option is held: that is not a tap.
    manager.handleKeyDown(keyDown(0, at: 100.1))
    manager.handle(flagsChanged(key: .leftOption, down: false, at: 100.2))

    #expect(fired().isEmpty)
}

@Test func unboundModifierDoesNothing() {
    let (manager, fired) = makeManager([
        SingleModifierBinding(modifier: .leftOption, inputSourceID: "com.apple.keylayout.ABC")
    ])

    manager.handle(flagsChanged(key: .leftShift, down: true, at: 100))
    manager.handle(flagsChanged(key: .leftShift, down: false, at: 100.1))

    #expect(fired().isEmpty)
}

/// A configuration written before the left/right split can contain both
/// "option" and "leftOption". They decode to the same key, and building the
/// binding table with `uniqueKeysWithValues:` used to trap.
@Test func duplicateBindingsDoNotCrash() {
    let manager = SingleModifierManager()
    manager.sync([
        SingleModifierBinding(modifier: .leftOption, inputSourceID: "com.apple.keylayout.ABC"),
        SingleModifierBinding(modifier: .leftOption, inputSourceID: "com.tencent.inputmethod.wetype.pinyin")
    ])
}
