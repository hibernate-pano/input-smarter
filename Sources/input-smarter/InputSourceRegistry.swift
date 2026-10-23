import Carbon
import Foundation

/// Keys used by the Text Input Sources API.
///
/// The `kTISProperty*` symbols are exported by HIToolbox but are no longer
/// declared in the modern SDK headers, so their real string values differ
/// from what the symbol names suggest (e.g. `kTISPropertyInputSourceIsEnabled`
/// is actually `"TSMInputSourcePropertyIsEnabled"`). The literals below were
/// read out of the running system with `dlsym`; `TISPropertyKeyTests` asserts
/// they still match the exported symbols.
enum TISKey {
    static let inputSourceID = "TISPropertyInputSourceID" as CFString
    static let category = "TISPropertyInputSourceCategory" as CFString
    static let type = "TISPropertyInputSourceType" as CFString
    static let isEnabled = "TSMInputSourcePropertyIsEnabled" as CFString
    static let isSelectCapable = "TISPropertyInputSourceIsSelectCapable" as CFString
    static let isASCIICapable = "TISPropertyInputSourceIsASCIICapable" as CFString
    static let inputModeID = "TSMInputSourcePropertyInputMode" as CFString
    static let bundleID = "TSMInputSourcePropertyBundleID" as CFString
    static let localizedName = "TSMInputSourcePropertyLocalizedName" as CFString
    /// The `UCKeyboardLayout` of the current keyboard layout, used to turn a
    /// virtual key code into the character it produces.
    static let unicodeKeyLayoutData = "TISPropertyUnicodeKeyLayoutData" as CFString

    static let categoryKeyboard = "TISCategoryKeyboardInputSource" as CFString
}

/// Identifier for one selectable input source.
///
/// A source is identified by its TIS input-source id plus, for mode-enabled
/// third-party IMEs, the id of the selected input mode. macOS reports these as
/// two separate properties, so we keep them separate and join them with `::`
/// when we need a single storable string — the same encoding Input Source Pro
/// stores in its Core Data `inputSourceId` column.
struct InputSourceID: Hashable, Codable, CustomStringConvertible {
    /// e.g. `com.apple.keylayout.ABC`, `com.tencent.inputmethod.wetype.pinyin`
    var sourceID: String
    /// e.g. `com.tencent.inputmethod.wetype.pinyin`; nil for keyboard layouts
    var modeID: String?

    init(sourceID: String, modeID: String? = nil) {
        self.sourceID = sourceID
        self.modeID = (modeID?.isEmpty ?? true) ? nil : modeID
    }

    /// Parse the `sourceID::modeID` composite form.
    init(composite: String) {
        if let separator = composite.range(of: "::") {
            self.sourceID = String(composite[composite.startIndex..<separator.lowerBound])
            let mode = String(composite[separator.upperBound...])
            self.modeID = mode.isEmpty ? nil : mode
        } else {
            self.sourceID = composite
            self.modeID = nil
        }
    }

    /// The storable composite form: `sourceID` alone, or `sourceID::modeID`.
    var composite: String {
        guard let modeID else { return sourceID }
        return "\(sourceID)::\(modeID)"
    }

    var description: String { composite }
}

/// A selectable input source as reported by TIS.
struct InputSourceInfo: Hashable, Identifiable {
    let id: InputSourceID
    let name: String
    let bundleID: String
    let isASCIICapable: Bool
    /// True for keyboard layouts (ABC), false for full input methods (pinyin).
    let isKeyboardLayout: Bool

    var displayName: String { name.isEmpty ? id.sourceID : name }
}

/// Reads and drives the system input source via the Text Input Sources API.
///
/// This is the same API Input Source Pro uses: `TISCreateInputSourceList` to
/// enumerate, `TISCopyCurrentKeyboardInputSource` to read the active one and
/// `TISSelectInputSource` to switch.
enum InputSourceRegistry {
    /// Enumerate the input sources the user has actually enabled and can pick.
    ///
    /// `includeAllInstalled: false` makes TIS return only the enabled sources
    /// (the alternative returns ~330 mostly-disabled system layouts, which the
    /// SDK header explicitly warns about). The `isSelectCapable` filter then
    /// drops the IME bodies that cannot be selected directly.
    static func availableSources() -> [InputSourceInfo] {
        let list = enabledKeyboardSources()
        return list.compactMap { info(from: $0) }
            .filter(\.isSelectable)
            .map(\.info)
            .sorted { lhs, rhs in
                // ASCII-capable layouts first: they are the "switch to English"
                // target and the most common destination.
                if lhs.isASCIICapable != rhs.isASCIICapable { return lhs.isASCIICapable }
                return lhs.displayName < rhs.displayName
            }
    }

    /// The enabled keyboard-category input sources.
    private static func enabledKeyboardSources() -> [TISInputSource] {
        let filter = [TISKey.category as String: TISKey.categoryKeyboard as String] as CFDictionary
        let list = TISCreateInputSourceList(filter, false).takeRetainedValue() as? [TISInputSource] ?? []
        return list
    }

    private struct RawInfo {
        var info: InputSourceInfo
        var isSelectable: Bool
    }

    private static func info(from source: TISInputSource) -> RawInfo? {
        guard let id = string(TISKey.inputSourceID, in: source) else { return nil }
        let mode = string(TISKey.inputModeID, in: source)
        let type = string(TISKey.type, in: source) ?? ""
        let info = InputSourceInfo(
            id: InputSourceID(sourceID: id, modeID: mode),
            name: string(TISKey.localizedName, in: source) ?? "",
            bundleID: string(TISKey.bundleID, in: source) ?? "",
            isASCIICapable: boolean(TISKey.isASCIICapable, in: source),
            isKeyboardLayout: type == "TISTypeKeyboardLayout"
        )
        return RawInfo(
            info: info,
            isSelectable: boolean(TISKey.isEnabled, in: source)
                && boolean(TISKey.isSelectCapable, in: source)
        )
    }

    /// The currently active input source.
    ///
    /// When an IME is active this reports the IME's *input mode* source, not
    /// the keyboard layout behind it — which is why the mode id is part of the
    /// identity.
    static func current() -> InputSourceID? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let id = string(TISKey.inputSourceID, in: source) else { return nil }
        return InputSourceID(sourceID: id, modeID: string(TISKey.inputModeID, in: source))
    }

    /// Switch to `target`. Returns false if the source is unknown or the
    /// system refuses the switch.
    @discardableResult
    static func select(_ target: InputSourceID) -> Bool {
        guard let source = find(target) else { return false }
        return TISSelectInputSource(source) == noErr
    }

    /// Resolve a stored identifier to a live TIS source.
    static func find(_ target: InputSourceID) -> TISInputSource? {
        var fallback: TISInputSource?
        for source in enabledKeyboardSources() {
            guard let id = string(TISKey.inputSourceID, in: source) else { continue }
            guard id == target.sourceID else { continue }
            let mode = string(TISKey.inputModeID, in: source)
            if let want = target.modeID {
                // A mode-enabled IME stores "source::mode"; match both halves.
                if mode == want { return source }
            } else if mode == nil || mode?.isEmpty == true {
                return source
            } else if fallback == nil {
                // The id names an input method that has modes, but no mode was
                // given: fall back to the first mode of that source.
                fallback = source
            }
        }
        return fallback
    }

    /// The canonical `sourceID::modeID` form of an identifier.
    ///
    /// A bare input method id (`com.tencent.inputmethod.wetype.pinyin`) is
    /// resolved to the composite form the system itself uses, so that a rule
    /// stores the same string the current-source comparison expects.
    static func normalize(_ composite: String) -> String {
        let target = InputSourceID(composite: composite)
        guard let source = find(target) else { return composite }
        let mode = string(TISKey.inputModeID, in: source)
        return InputSourceID(sourceID: target.sourceID, modeID: mode).composite
    }

    // MARK: - Raw property access

    private static func property(_ key: CFString, in source: TISInputSource) -> CFTypeRef? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue()
    }

    private static func string(_ key: CFString, in source: TISInputSource) -> String? {
        guard let value = property(key, in: source) else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }

    private static func boolean(_ key: CFString, in source: TISInputSource) -> Bool {
        guard let value = property(key, in: source) else { return false }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue(value as! CFBoolean)
    }
}
