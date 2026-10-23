import Foundation

/// A rule binding one application to one input source.
///
/// When the app becomes frontmost, `inputSourceID` is selected. When the user
/// leaves the app, `restoreKeyboard` decides whether the previous input source
/// is restored.
struct AppRule: Codable, Identifiable, Hashable {
    var bundleID: String
    var bundleName: String
    /// Composite `sourceID::modeID` form; see `InputSourceID`.
    var inputSourceID: String
    /// Switch back to the previous input source when this app is deactivated.
    var restoreKeyboard: Bool
    /// Carried over from Input Source Pro, but not acted on: the floating
    /// current-source indicator is not implemented (see the README).
    var hideIndicator: Bool

    var id: String { bundleID }

    init(bundleID: String, bundleName: String, inputSourceID: String,
         restoreKeyboard: Bool = false, hideIndicator: Bool = false) {
        self.bundleID = bundleID
        self.bundleName = bundleName
        self.inputSourceID = inputSourceID
        self.restoreKeyboard = restoreKeyboard
        self.hideIndicator = hideIndicator
    }

    enum CodingKeys: String, CodingKey {
        case bundleID, bundleName, inputSourceID, restoreKeyboard, hideIndicator
    }

    /// Decoded leniently: a configuration written by an older version is
    /// missing keys, and a missing key must not cost the user the whole file.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        bundleName = try container.decodeIfPresent(String.self, forKey: .bundleName) ?? bundleID
        inputSourceID = try container.decode(String.self, forKey: .inputSourceID)
        restoreKeyboard = try container.decodeIfPresent(Bool.self, forKey: .restoreKeyboard) ?? false
        hideIndicator = try container.decodeIfPresent(Bool.self, forKey: .hideIndicator) ?? false
    }
}

/// A hotkey that cycles through a group of input sources.
struct HotkeyBinding: Codable, Identifiable, Hashable {
    var id: UUID
    /// Virtual key code (see `KeyboardLayout.h`).
    var keyCode: UInt16
    /// Carbon modifier mask (`cmdKey` | `optionKey` | ...).
    var modifiers: UInt32
    /// Composite ids cycled through, in order.
    var inputSourceIDs: [String]
    /// Human readable label shown in the menu.
    var title: String

    init(id: UUID = UUID(), keyCode: UInt16, modifiers: UInt32,
         inputSourceIDs: [String], title: String = "") {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.inputSourceIDs = inputSourceIDs
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case id, keyCode, modifiers, inputSourceIDs, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        modifiers = try container.decode(UInt32.self, forKey: .modifiers)
        inputSourceIDs = try container.decodeIfPresent([String].self, forKey: .inputSourceIDs) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    }
}

/// A rule that applies only while a browser's address bar has focus.
struct BrowserRule: Codable, Identifiable, Hashable {
    /// Bundle identifier of the browser, e.g. `com.google.Chrome`.
    var browserBundleID: String
    /// Input source used while the address bar is focused.
    var inputSourceID: String
    /// Switch back to the page's input source when focus leaves the address bar.
    var restoreKeyboard: Bool
    var enabled: Bool

    var id: String { browserBundleID }

    init(browserBundleID: String, inputSourceID: String,
         restoreKeyboard: Bool = true, enabled: Bool = true) {
        self.browserBundleID = browserBundleID
        self.inputSourceID = inputSourceID
        self.restoreKeyboard = restoreKeyboard
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case browserBundleID, inputSourceID, restoreKeyboard, enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        browserBundleID = try container.decode(String.self, forKey: .browserBundleID)
        inputSourceID = try container.decode(String.self, forKey: .inputSourceID)
        restoreKeyboard = try container.decodeIfPresent(Bool.self, forKey: .restoreKeyboard) ?? true
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// Everything the app persists between launches.
struct Configuration: Codable {
    var appRules: [AppRule] = []
    var hotkeys: [HotkeyBinding] = []
    var singleModifierBindings: [SingleModifierBinding] = []
    var browserRules: [BrowserRule] = []
    /// Input source to fall back to when no rule applies.
    var defaultInputSourceID: String?

    enum CodingKeys: String, CodingKey {
        case appRules, hotkeys, singleModifierBindings, browserRules, defaultInputSourceID
    }

    init() {}

    /// Decoded leniently.
    ///
    /// The synthesized `Decodable` conformance ignores the property defaults
    /// above and throws `keyNotFound` for a missing key, which would turn one
    /// outdated configuration file into an empty configuration — and the next
    /// write would then overwrite the user's rules with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appRules = try container.decodeIfPresent([AppRule].self, forKey: .appRules) ?? []
        hotkeys = try container.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeys) ?? []
        singleModifierBindings = try container.decodeIfPresent([SingleModifierBinding].self, forKey: .singleModifierBindings) ?? []
        browserRules = try container.decodeIfPresent([BrowserRule].self, forKey: .browserRules) ?? []
        defaultInputSourceID = try container.decodeIfPresent(String.self, forKey: .defaultInputSourceID)
    }

    func rule(for bundleID: String) -> AppRule? {
        appRules.first { $0.bundleID == bundleID }
    }
}
