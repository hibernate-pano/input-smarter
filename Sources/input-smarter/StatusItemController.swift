import AppKit
import Carbon

/// The menu bar UI.
///
/// Deliberately minimal: this is a personal tool, so the menu only has to
/// expose what cannot be expressed as an automatic rule — see and change the
/// current source, and bind the current app to a source.
final class StatusItemController {
    /// What a menu item acts on.
    ///
    /// The bundle id is captured when the menu is built: re-reading the
    /// frontmost application when the item is clicked would bind a different
    /// app than the one the menu names.
    private struct BindingTarget {
        let bundleID: String
        let bundleName: String
        let inputSourceID: String
    }

    private let statusItem: NSStatusItem
    private let store: RuleStore
    private let onSelect: (InputSourceID) -> Void
    private let onSetRule: (String, String, InputSourceID) -> Void

    /// Called after a rule was removed, so the input source can be given
    /// back right away instead of on the next configuration change.
    var onRulesChanged: (() -> Void)?

    init(
        store: RuleStore = .shared,
        onSelect: @escaping (InputSourceID) -> Void,
        onSetRule: @escaping (String, String, InputSourceID) -> Void
    ) {
        self.store = store
        self.onSelect = onSelect
        self.onSetRule = onSetRule

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "character.textbox",
            accessibilityDescription: "input-smarter"
        )
        rebuild()
    }

    /// Rebuilds the menu from the current configuration and system state.
    func rebuild() {
        let menu = NSMenu()

        let current = InputSourceRegistry.current()
        let currentItem = NSMenuItem(title: "当前：\(current?.composite ?? "未知")", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        menu.addItem(.separator())

        // Manual switching.
        let sources = InputSourceRegistry.availableSources()
        let sourcesItem = NSMenuItem(title: "切换输入法", action: nil, keyEquivalent: "")
        let sourcesMenu = NSMenu()
        for source in sources {
            let item = NSMenuItem(
                title: source.displayName,
                action: #selector(selectSource(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = source.id.composite
            item.state = (source.id == current) ? .on : .off
            sourcesMenu.addItem(item)
        }
        sourcesItem.submenu = sourcesMenu
        menu.addItem(sourcesItem)

        // Bind the current app to a source.
        if let front = NSWorkspace.shared.frontmostApplication,
           let bundleID = front.bundleIdentifier,
           bundleID != Bundle.main.bundleIdentifier {
            let bundleName = front.localizedName ?? bundleID
            let bindItem = NSMenuItem(
                title: "当前 App（\(bundleName)）固定输入法",
                action: nil,
                keyEquivalent: ""
            )
            let bindMenu = NSMenu()
            // The source this app is currently pinned to. It gets a checkmark,
            // so the menu shows the state of the rule instead of a bare list.
            let existing = store.configuration.rule(for: bundleID)
            for item in Self.bindMenuItems(
                sources: sources,
                rule: existing,
                bundleID: bundleID,
                bundleName: bundleName
            ) {
                item.target = self
                bindMenu.addItem(item)
            }
            if let existing {
                let remove = NSMenuItem(title: "取消固定", action: #selector(removeRule(_:)), keyEquivalent: "")
                remove.target = self
                remove.representedObject = BindingTarget(
                    bundleID: bundleID,
                    bundleName: bundleName,
                    inputSourceID: existing.inputSourceID
                )
                bindMenu.addItem(.separator())
                bindMenu.addItem(remove)
            }
            bindItem.submenu = bindMenu
            menu.addItem(bindItem)
        }

        // Existing rules.
        let rules = store.configuration.appRules
        if !rules.isEmpty {
            let rulesItem = NSMenuItem(title: "已配置的规则", action: nil, keyEquivalent: "")
            let rulesMenu = NSMenu()
            for rule in rules {
                let item = NSMenuItem(
                    title: "\(rule.bundleName)：\(rule.inputSourceID)\(rule.restoreKeyboard ? "（离开时恢复）" : "")",
                    action: #selector(toggleRule(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = rule.bundleID
                item.indentationLevel = 1
                rulesMenu.addItem(item)
            }
            rulesItem.submenu = rulesMenu
            menu.addItem(rulesItem)
        }

        // Hotkeys and single modifier bindings. They are configured from the
        // command line, so they are shown here: a shortcut the user cannot
        // see is a shortcut they cannot check.
        let config = store.configuration
        if !config.hotkeys.isEmpty || !config.singleModifierBindings.isEmpty {
            let shortcutsItem = NSMenuItem(title: "快捷键", action: nil, keyEquivalent: "")
            let shortcutsMenu = NSMenu()
            for hotkey in config.hotkeys {
                let item = NSMenuItem(
                    title: "⌨︎ \(describe(hotkey)) → \(hotkey.inputSourceIDs.joined(separator: " → "))",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                item.indentationLevel = 1
                shortcutsMenu.addItem(item)
            }
            for binding in config.singleModifierBindings {
                let item = NSMenuItem(
                    title: "⌨︎ \(binding.modifier.displayName)（\(binding.trigger.displayName)）→ \(binding.inputSourceID)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                item.indentationLevel = 1
                shortcutsMenu.addItem(item)
            }
            shortcutsItem.submenu = shortcutsMenu
            menu.addItem(shortcutsItem)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// The items of the "bind the current app to a source" submenu.
    ///
    /// The source the app is currently pinned to carries a checkmark, so the
    /// menu shows the state of the rule rather than a bare list of sources.
    ///
    /// Static and free of the status item, so the tests can build it.
    static func bindMenuItems(
        sources: [InputSourceInfo],
        rule: AppRule?,
        bundleID: String,
        bundleName: String
    ) -> [NSMenuItem] {
        let bound = rule.map { InputSourceID(composite: $0.inputSourceID) }
        return sources.map { source in
            let item = NSMenuItem(
                title: source.displayName,
                action: #selector(setRule(_:)),
                keyEquivalent: ""
            )
            item.representedObject = BindingTarget(
                bundleID: bundleID,
                bundleName: bundleName,
                inputSourceID: source.id.composite
            )
            item.indentationLevel = 1
            item.state = (bound == source.id) ? .on : .off
            return item
        }
    }

    /// A readable description of a hotkey.
    private func describe(_ hotkey: HotkeyBinding) -> String {
        var parts: [String] = []
        if hotkey.modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if hotkey.modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if hotkey.modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if hotkey.modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        parts.append(Self.keyName(hotkey.keyCode))
        return parts.joined()
    }

    /// The character a virtual key code produces on the current layout.
    private static func keyName(_ keyCode: UInt16) -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
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

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let composite = sender.representedObject as? String else { return }
        onSelect(InputSourceID(composite: composite))
        rebuild()
    }

    @objc private func setRule(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? BindingTarget else { return }
        onSetRule(target.bundleID, target.bundleName, InputSourceID(composite: target.inputSourceID))
        rebuild()
    }

    @objc private func removeRule(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? BindingTarget else { return }
        store.removeAppRule(bundleID: target.bundleID)
        onRulesChanged?()
        rebuild()
    }

    @objc private func toggleRule(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        store.removeAppRule(bundleID: bundleID)
        onRulesChanged?()
        rebuild()
    }
}
