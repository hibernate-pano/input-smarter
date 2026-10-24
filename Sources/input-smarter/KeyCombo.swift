import AppKit
import Carbon
import Foundation

/// A key together with the modifiers that have to be held down with it.
///
/// The same combination is registered with Carbon, shown to the user and
/// recorded from the keyboard, so it is kept in one place.
struct KeyCombo: Equatable, Hashable {
    /// Virtual key code (see `KeyboardLayout.h`).
    var keyCode: UInt16
    /// Carbon modifier mask (`cmdKey` | `optionKey` | ...).
    var modifiers: UInt32

    /// The combination as it is shown to the user, e.g. "⌥空格".
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// The Carbon modifier mask of the modifier flags of an event.
    ///
    /// The flags also carry states that are not modifiers — the caps lock and
    /// the function key — and those must not end up in the mask.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// The name of the key.
    ///
    /// Most keys produce a character on the current keyboard layout; a few
    /// have none of their own and get a name instead.
    static func keyName(_ keyCode: UInt16) -> String {
        switch keyCode {
        case UInt16(kVK_Space): return "空格"
        case UInt16(kVK_Return): return "回车"
        case UInt16(kVK_Tab): return "Tab"
        case UInt16(kVK_Escape): return "Esc"
        case UInt16(kVK_Delete): return "退格"
        case UInt16(kVK_ForwardDelete): return "删除"
        case UInt16(kVK_LeftArrow): return "←"
        case UInt16(kVK_RightArrow): return "→"
        case UInt16(kVK_DownArrow): return "↓"
        case UInt16(kVK_UpArrow): return "↑"
        default: break
        }

        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, TISKey.unicodeKeyLayoutData) else {
            return "键\(keyCode)"
        }
        let cfData = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(cfData) else { return "键\(keyCode)" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0, let scalar = UnicodeScalar(characters[0]) else {
            return "键\(keyCode)"
        }
        return String(Character(scalar).uppercased())
    }
}
