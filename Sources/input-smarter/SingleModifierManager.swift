import AppKit
import Carbon
import Foundation

/// A single physical modifier key.
///
/// The left and right variants are separate keys on purpose: macOS reports
/// them under different virtual key codes, and people do bind them
/// differently (left Option to switch input sources, right Option for
/// something else).
enum ModifierKey: String, Codable, CaseIterable, Identifiable {
    case leftShift
    case rightShift
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand

    var id: String { rawValue }

    /// Virtual key code of the key.
    var keyCode: UInt16 {
        switch self {
        case .leftShift: return UInt16(kVK_Shift)
        case .rightShift: return UInt16(kVK_RightShift)
        case .leftControl: return UInt16(kVK_Control)
        case .rightControl: return UInt16(kVK_RightControl)
        case .leftOption: return UInt16(kVK_Option)
        case .rightOption: return UInt16(kVK_RightOption)
        case .leftCommand: return UInt16(kVK_Command)
        case .rightCommand: return UInt16(kVK_RightCommand)
        }
    }

    /// The `NSEvent.ModifierFlags` member this key contributes to.
    ///
    /// This is the *family* of the key: both shifts report `.shift`. The flags
    /// cannot tell the two sides apart, which is why the state machine below
    /// combines them with the key code of the event.
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .leftShift, .rightShift: return .shift
        case .leftControl, .rightControl: return .control
        case .leftOption, .rightOption: return .option
        case .leftCommand, .rightCommand: return .command
        }
    }

    var displayName: String {
        switch self {
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        }
    }

    /// Identify the key behind a virtual key code.
    static func from(keyCode: UInt16) -> ModifierKey? {
        switch keyCode {
        case UInt16(kVK_Shift): return .leftShift
        case UInt16(kVK_RightShift): return .rightShift
        case UInt16(kVK_Control): return .leftControl
        case UInt16(kVK_RightControl): return .rightControl
        case UInt16(kVK_Option): return .leftOption
        case UInt16(kVK_RightOption): return .rightOption
        case UInt16(kVK_Command): return .leftCommand
        case UInt16(kVK_RightCommand): return .rightCommand
        default: return nil
        }
    }

    /// Accept the short forms (`option`) in addition to the exact ones
    /// (`leftOption`), and keep reading configurations written before the
    /// left/right split existed.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "shift": self = .leftShift
        case "control": self = .leftControl
        case "option": self = .leftOption
        case "command": self = .leftCommand
        default:
            guard let key = ModifierKey(rawValue: raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "unknown modifier key '\(raw)'"))
            }
            self = key
        }
    }

    /// Parse a user-supplied modifier name.
    static func parse(_ name: String) -> ModifierKey? {
        switch name.lowercased() {
        case "shift", "leftshift": return .leftShift
        case "rightshift": return .rightShift
        case "control", "ctrl", "leftcontrol": return .leftControl
        case "rightcontrol", "rightctrl": return .rightControl
        case "option", "alt", "leftoption": return .leftOption
        case "rightoption", "rightalt": return .rightOption
        case "command", "cmd", "leftcommand": return .leftCommand
        case "rightcommand", "rightcmd": return .rightCommand
        default: return ModifierKey(rawValue: name.lowercased())
        }
    }
}

/// How many taps the modifier needs before it fires.
enum SingleModifierTrigger: String, Codable, CaseIterable, Identifiable {
    case singlePress
    case doublePress

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singlePress: return "单击"
        case .doublePress: return "双击"
        }
    }
}

/// Binds one modifier key to an input source.
struct SingleModifierBinding: Codable, Identifiable, Hashable {
    var modifier: ModifierKey
    var trigger: SingleModifierTrigger
    /// Composite `sourceID::modeID` form.
    var inputSourceID: String

    var id: String { modifier.rawValue }

    init(modifier: ModifierKey, trigger: SingleModifierTrigger = .singlePress, inputSourceID: String) {
        self.modifier = modifier
        self.trigger = trigger
        self.inputSourceID = inputSourceID
    }
}

/// Detects modifier taps and reports them.
///
/// Uses `NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged])`, which
/// — unlike a `CGEventTap` on key events — does not require the Input
/// Monitoring permission.
///
/// A modifier counts as "tapped" when it is pressed and released within
/// `maxHoldDuration`. Holding it longer (for example to type a
/// Command-shortcut) deliberately does not fire.
///
/// The identity of the key comes from the event's virtual key code, not from
/// the modifier flags: the flags only say "some shift is down", so they
/// cannot tell left Shift from right Shift, and they stay set while the
/// other side is still held.
///
/// That is also why a `flagsChanged` event alone does not say whether its key
/// went down or up. The state machine combines three pieces of information:
///
/// * the event's key code, which says *which* key changed;
/// * the family flag (`.shift`, `.option`, …), which says whether *any* key
///   of that family is currently held;
/// * the keys the manager already believes are held.
///
/// From those it can tell a press from a release, and it can recognise the
/// case the flags alone cannot express: releasing the left shift while the
/// right shift is still down. The family flag stays set then, so the event
/// looks like a press — but the manager knows the key was already held.
final class SingleModifierManager {
    /// Called when a modifier is tapped and its binding fires.
    var onTrigger: ((SingleModifierBinding) -> Void)?

    /// Holding a modifier longer than this does not count as a tap.
    private let maxHoldDuration: TimeInterval = 0.8
    /// Two taps within this window count as a double press.
    private let doublePressInterval: TimeInterval = 0.35
    /// A key pressed this recently before the release cancels the tap.
    private let otherKeyPressSuppressInterval: TimeInterval = 0.2

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyDownMonitor: Any?

    /// A modifier key that is currently held down.
    private struct Press {
        /// When the key went down.
        var startedAt: TimeInterval
        /// True when another modifier was held at the same time: that is a
        /// combination, not a tap.
        var chorded: Bool
    }

    /// The modifier keys currently held down.
    private var pressedAt: [ModifierKey: Press] = [:]
    /// Timestamp of the last tap per key, for double press detection.
    private var lastTapAt: [ModifierKey: TimeInterval] = [:]
    /// Timestamp of the most recent key-down per virtual key code.
    private var lastKeyDownAt: [UInt16: TimeInterval] = [:]
    private var bindings: [ModifierKey: SingleModifierBinding] = [:]
    /// Whether the family flag was set the last time an event for that family
    /// arrived. Keyed by the flag's raw value: `NSEvent.ModifierFlags` is not
    /// `Hashable`.
    private var familyWasDown: [UInt: Bool] = [:]

    /// The global and the local monitor can both report the same event.
    private var lastEventTimestamp: TimeInterval = 0
    private var lastEventKeyCode: UInt16 = 0
    /// Whether the key-down monitor delivers anything at all.
    private var sawKeyDown = false

    func start() {
        guard globalMonitor == nil else { return }
        seedFamilyState()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handle(event)
            return event
        }
        // Key presses let us ignore a "tap" that was really the user typing
        // with the modifier held down. This needs the Accessibility
        // permission, so it is best effort: without it the monitor is
        // installed but never delivers anything.
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        globalMonitor = nil
        localMonitor = nil
        keyDownMonitor = nil
    }

    /// Replace the bindings.
    ///
    /// Two bindings for the same key are possible in a configuration written
    /// by an older version (`option` and `leftOption` decode to the same
    /// key), so the last one wins instead of trapping.
    func sync(_ newBindings: [SingleModifierBinding]) {
        var merged: [ModifierKey: SingleModifierBinding] = [:]
        for binding in newBindings {
            if merged[binding.modifier] != nil {
                Log.error("[modifier] duplicate binding for \(binding.modifier.rawValue), keeping the last one")
            }
            merged[binding.modifier] = binding
        }
        bindings = merged
    }

    /// Handles one flagsChanged event.
    ///
    /// Not private: the tests drive the same state machine with hand-built
    /// events, because a synthetic key press cannot make the window server
    /// update the real modifier state.
    func handle(_ event: NSEvent) {
        Log.debug("[modifier] raw flagsChanged keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue) ts=\(String(format: "%.3f", event.timestamp))")
        // The global and the local monitor can both report the same event.
        guard event.timestamp != lastEventTimestamp || event.keyCode != lastEventKeyCode else { return }
        lastEventTimestamp = event.timestamp
        lastEventKeyCode = event.keyCode

        guard let key = ModifierKey.from(keyCode: event.keyCode) else { return }

        var flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        flags.remove(.capsLock)
        let family = key.flag
        let familyIsDown = flags.contains(family)
        let familyWasDownBefore = familyWasDown[family.rawValue] ?? false
        familyWasDown[family.rawValue] = familyIsDown

        if familyIsDown {
            if pressedAt[key] == nil {
                // The key went down. Another modifier already held means this
                // is a combination, not a single key tap.
                let chorded = !pressedAt.isEmpty || familyWasDownBefore
                pressedAt[key] = Press(startedAt: event.timestamp, chorded: chorded)
                if chorded {
                    // The keys that were already held belong to the same
                    // combination, so they must not fire either.
                    for other in pressedAt.keys.filter({ $0 != key }) {
                        pressedAt[other]?.chorded = true
                    }
                }
                Log.debug("[modifier] \(key.rawValue) down held=\(pressedAt.keys.map(\.rawValue))")
            } else {
                // The family is still down, so this key was released while its
                // sibling stayed pressed: a combination, not a tap.
                pressedAt.removeValue(forKey: key)
                Log.debug("[modifier] \(key.rawValue) up (sibling still held)")
            }
            return
        }

        // The whole family is up, so this key was the last one released.
        guard let press = pressedAt.removeValue(forKey: key) else {
            forgetMissedReleases(family: family)
            Log.debug("[modifier] \(key.rawValue) up, not tracked")
            return
        }
        forgetMissedReleases(family: family)

        guard !press.chorded else {
            Log.debug("[modifier] \(key.rawValue) up, part of a combination")
            lastTapAt.removeValue(forKey: key)
            return
        }

        let holdDuration = event.timestamp - press.startedAt
        guard holdDuration <= maxHoldDuration else {
            Log.debug("[modifier] \(key.rawValue) up held=\(String(format: "%.2f", holdDuration))s, too long")
            return
        }

        if didPressOtherKeyRecently(before: event.timestamp, excluding: key) {
            // Typing with the modifier held down is not a tap.
            Log.debug("[modifier] \(key.rawValue) up, another key was pressed")
            lastTapAt.removeValue(forKey: key)
            return
        }

        fire(key, at: event.timestamp, heldFor: holdDuration)
    }

    func handleKeyDown(_ event: NSEvent) {
        if !sawKeyDown {
            sawKeyDown = true
            Log.debug("[modifier] keyDown monitor is delivering events (other-key suppression active)")
        }
        lastKeyDownAt[event.keyCode] = event.timestamp
        if let key = ModifierKey.from(keyCode: event.keyCode) {
            // The modifier's own press must not cancel its pending double
            // press: that press is the second half of the pair. A press of a
            // different modifier does cancel it.
            lastTapAt = lastTapAt.filter { $0.key == key }
        } else {
            // Any other key cancels a pending double press.
            lastTapAt.removeAll()
        }
    }

    /// Records the modifiers that are already held when the app starts.
    ///
    /// Without this a key that was down before the app launched would look
    /// like a press, and its release would look like a tap.
    private func seedFamilyState() {
        let flags = NSEvent.modifierFlags
        for family in Set(ModifierKey.allCases.map(\.flag.rawValue)) {
            familyWasDown[family] = flags.contains(NSEvent.ModifierFlags(rawValue: family))
        }
    }

    /// The family flag is clear, so every key of that family still tracked
    /// was released without an event — drop the stale entries, or they would
    /// block every later tap.
    private func forgetMissedReleases(family: NSEvent.ModifierFlags) {
        for key in pressedAt.keys.filter({ $0.flag == family }) {
            pressedAt.removeValue(forKey: key)
        }
    }

    private func didPressOtherKeyRecently(before timestamp: TimeInterval, excluding key: ModifierKey) -> Bool {
        let cutoff = timestamp - otherKeyPressSuppressInterval
        lastKeyDownAt = lastKeyDownAt.filter { $0.value >= cutoff }
        let excludedKeyCodes = Set([key.keyCode])
        let lastOther = lastKeyDownAt
            .filter { !excludedKeyCodes.contains($0.key) }
            .map(\.value)
            .max()
        guard let lastOther else { return false }
        return timestamp - lastOther <= otherKeyPressSuppressInterval
    }

    private func fire(_ key: ModifierKey, at timestamp: TimeInterval, heldFor holdDuration: TimeInterval) {
        guard let binding = bindings[key] else { return }
        Log.debug("[modifier] tap \(key.rawValue) held=\(String(format: "%.2f", holdDuration))s trigger=\(binding.trigger.rawValue)")

        switch binding.trigger {
        case .singlePress:
            onTrigger?(binding)
        case .doublePress:
            if let last = lastTapAt[key], timestamp - last <= doublePressInterval {
                lastTapAt.removeValue(forKey: key)
                onTrigger?(binding)
            } else {
                lastTapAt[key] = timestamp
            }
        }
    }
}
