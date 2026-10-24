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

    /// Called when the user asks for the settings window.
    var onOpenSettings: (() -> Void)?

    /// Called when the user asks to edit the hotkeys.
    var onOpenHotkeys: (() -> Void)?

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

        // The sources are read first: the name of the source that is in use
        // is the name of one of them.
        let sources = InputSourceRegistry.availableSources()
        let current = InputSourceRegistry.current()
        let currentItem = NSMenuItem(
            title: "当前：\(Self.currentSourceName(sources: sources, current: current))",
            action: nil,
            keyEquivalent: ""
        )
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        menu.addItem(.separator())

        // Manual switching.
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

        // The fallback input source: the one that is used when no rule
        // applies. It is a switch like any other, so it belongs here and not
        // in a window that has to be opened first.
        let defaultID = store.configuration.defaultInputSourceID
        let defaultItem = NSMenuItem(
            title: "默认输入法：\(Self.defaultSourceName(sources: sources, defaultID: defaultID))",
            action: nil,
            keyEquivalent: ""
        )
        let defaultMenu = NSMenu()
        for item in Self.defaultSourceMenuItems(sources: sources, defaultID: defaultID) {
            item.target = self
            item.action = #selector(setDefaultSource(_:))
            defaultMenu.addItem(item)
        }
        defaultItem.submenu = defaultMenu
        menu.addItem(defaultItem)

        // Launch at login.
        let launchAtLogin = Self.launchAtLoginItem(isEnabled: LoginItem.isEnabled)
        launchAtLogin.target = self
        launchAtLogin.action = #selector(toggleLaunchAtLogin(_:))
        menu.addItem(launchAtLogin)

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
                    title: "\(rule.bundleName)：\(Self.sourceName(rule.inputSourceID, in: sources))\(rule.restoreKeyboard ? "（离开时恢复）" : "")",
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
                    title: "⌨︎ \(KeyCombo(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers).display) → \(hotkey.inputSourceIDs.map { Self.sourceName($0, in: sources) }.joined(separator: " → "))",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                item.indentationLevel = 1
                shortcutsMenu.addItem(item)
            }
            for binding in config.singleModifierBindings {
                let item = NSMenuItem(
                    title: "⌨︎ \(binding.modifier.displayName)（\(binding.trigger.displayName)）→ \(Self.sourceName(binding.inputSourceID, in: sources))",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                item.indentationLevel = 1
                shortcutsMenu.addItem(item)
            }
            shortcutsMenu.addItem(.separator())
            let edit = NSMenuItem(title: "编辑…", action: #selector(openHotkeys(_:)), keyEquivalent: "")
            edit.target = self
            shortcutsMenu.addItem(edit)
            shortcutsItem.submenu = shortcutsMenu
            menu.addItem(shortcutsItem)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
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

    /// The items of the "default input source" submenu.
    ///
    /// The source that is the default is marked, so the menu shows the state
    /// of the setting instead of a bare list of sources. The first item takes
    /// the default away again.
    ///
    /// Static and free of the status item, so the tests can build it.
    static func defaultSourceMenuItems(
        sources: [InputSourceInfo],
        defaultID: String?
    ) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let follow = NSMenuItem(title: "跟随系统（不设默认）", action: nil, keyEquivalent: "")
        follow.state = (defaultID == nil) ? .on : .off
        follow.representedObject = ""
        items.append(follow)
        for source in sources {
            let item = NSMenuItem(title: source.displayName, action: nil, keyEquivalent: "")
            item.state = (source.id.composite == defaultID) ? .on : .off
            item.representedObject = source.id.composite
            items.append(item)
        }
        return items
    }

    /// The name of the fallback input source, for the title of the submenu.
    static func defaultSourceName(sources: [InputSourceInfo], defaultID: String?) -> String {
        guard let defaultID else { return "跟随系统" }
        return sources.first { $0.id.composite == defaultID }?.displayName ?? defaultID
    }

    /// The name of the input source that is in use.
    ///
    /// The system reports an identifier, but the user knows the source by
    /// its name. A source that is not in the list keeps the last part of its
    /// identifier, which is the name the system gave it.
    static func currentSourceName(sources: [InputSourceInfo], current: InputSourceID?) -> String {
        guard let current else { return "未知" }
        if let source = sources.first(where: { $0.id == current }) {
            return source.displayName
        }
        return current.sourceID.split(separator: ".").last.map(String.init) ?? current.sourceID
    }

    /// The name of an input source, for the menu.
    static func sourceName(_ composite: String, in sources: [InputSourceInfo]) -> String {
        if let source = sources.first(where: { $0.id.composite == composite }) {
            return source.displayName
        }
        return InputSourceID(composite: composite).sourceID
            .split(separator: ".").last.map(String.init) ?? composite
    }

    /// The item that turns launch at login on and off.
    static func launchAtLoginItem(isEnabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: "开机自启", action: nil, keyEquivalent: "")
        item.state = isEnabled ? .on : .off
        return item
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let composite = sender.representedObject as? String else { return }
        onSelect(InputSourceID(composite: composite))
        rebuild()
    }

    /// Make an input source the fallback one.
    ///
    /// An empty identifier means "no fallback": the system decides which
    /// input source is used when no rule applies.
    @objc private func setDefaultSource(_ sender: NSMenuItem) {
        guard let composite = sender.representedObject as? String else { return }
        store.setDefaultInputSource(composite.isEmpty ? nil : composite)
        Log.debug("[config] default source = \(composite.isEmpty ? "none" : composite)")
        rebuild()
    }

    /// Turn launch at login on or off.
    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        let result = LoginItem.set(!LoginItem.isEnabled)
        Log.debug("[login] \(result.message)")
        if !result.success { presentError(result.message) }
        rebuild()
    }

    /// Open the settings window on the page where the hotkeys are edited.
    @objc private func openHotkeys(_ sender: Any?) {
        onOpenHotkeys?()
    }

    /// Show a failure to the user.
    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "没能改成功"
        alert.informativeText = message
        alert.runModal()
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

    @objc private func openSettings(_ sender: Any?) {
        onOpenSettings?()
    }
}
