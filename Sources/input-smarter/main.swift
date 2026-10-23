import AppKit
import ApplicationServices

// Entry point for the menu bar app.
//
// The app is an accessory (no Dock icon) and holds a single permission:
// Accessibility. Input Source Pro does the same — its bundle only carries a
// `kTCCServiceAccessibility` grant and no Input Monitoring grant — which is
// why every feature here is built on NSWorkspace, AX and Carbon hotkeys.

final class AppController {
    private let store = RuleStore.shared
    private let activationWatcher = AppActivationWatcher()
    private let hotkeys = HotkeyManager()
    private let singleModifiers = SingleModifierManager()
    private let focusWatcher = AXFocusWatcher()
    private var statusItem: StatusItemController?
    /// Source that was active before a browser rule took over.
    private var browserRuleSuspendedSource: InputSourceID?

    func start() {
        requestAccessibilityIfNeeded()

        HotkeyManager.shared = hotkeys
        hotkeys.start()
        hotkeys.onCycle = { [weak self] binding in
            self?.cycle(binding)
        }

        singleModifiers.start()
        singleModifiers.onTrigger = { [weak self] binding in
            InputSourceRegistry.select(InputSourceID(composite: binding.inputSourceID))
            Log.debug("[modifier] trigger \(binding.modifier.rawValue) -> \(binding.inputSourceID)")
            self?.statusItem?.rebuild()
        }
        singleModifiers.sync(store.configuration.singleModifierBindings)

        activationWatcher.start()
        focusWatcher.start()
        focusWatcher.onFocusChange = { [weak self] bundleID, isAddressBar in
            self?.handleBrowserFocus(bundleID: bundleID, isAddressBar: isAddressBar)
        }

        statusItem = StatusItemController(
            store: store,
            onSelect: { [weak self] id in
                InputSourceRegistry.select(id)
                self?.statusItem?.rebuild()
            },
            onSetRule: { [weak self] bundleID, bundleName, id in
                guard let self else { return }
                // The menu has no toggle for "restore when leaving", so it
                // must not silently drop the setting of an existing rule.
                let existing = self.store.configuration.rule(for: bundleID)
                self.store.setAppRule(AppRule(
                    bundleID: bundleID,
                    bundleName: bundleName,
                    inputSourceID: id.composite,
                    restoreKeyboard: existing?.restoreKeyboard ?? false
                ))
                self.statusItem?.rebuild()
            }
        )

        observeConfigurationChanges()
        observeApplicationActivation()
        hotkeys.sync(store.configuration.hotkeys)
    }

    /// Re-read the configuration when the CLI changes it.
    ///
    /// The CLI runs in a separate process, so the change notification has to
    /// arrive over the distributed centre.
    private func observeConfigurationChanges() {
        let reload: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            Log.debug("[config] reloaded")
            self.hotkeys.sync(self.store.configuration.hotkeys)
            self.singleModifiers.sync(self.store.configuration.singleModifierBindings)
            self.statusItem?.rebuild()
            // A rule that was just added for the frontmost app has to take
            // effect now, and a rule that was just removed has to give the
            // user's input source back.
            self.activationWatcher.reapply()
        }
        NotificationCenter.default.addObserver(
            forName: store.onChange,
            object: nil,
            queue: .main,
            using: reload
        )
        DistributedNotificationCenter.default().addObserver(
            forName: store.onChange,
            object: nil,
            queue: .main,
            using: reload
        )
    }

    /// Keep the menu in step with the frontmost application.
    private func observeApplicationActivation() {
        var lastBundleID: String?
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            guard bundleID != lastBundleID else { return }
            lastBundleID = bundleID
            self?.statusItem?.rebuild()
        }
    }

    /// Ask for Accessibility once; without it neither the AX focus watcher
    /// nor the permission check can work.
    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Cycle to the next source in the hotkey's group.
    private func cycle(_ binding: HotkeyBinding) {
        guard !binding.inputSourceIDs.isEmpty else { return }
        let ids = binding.inputSourceIDs.map(InputSourceID.init(composite:))
        guard let current = InputSourceRegistry.current(),
              let index = ids.firstIndex(of: current) else {
            if let first = ids.first { InputSourceRegistry.select(first) }
            return
        }
        let next = ids[(index + 1) % ids.count]
        let ok = InputSourceRegistry.select(next)
        Log.debug("[hotkey] cycle \(current.composite) -> \(next.composite) select=\(ok)")
    }

    /// Apply or undo a browser rule when the address bar focus changes.
    private func handleBrowserFocus(bundleID: String, isAddressBar: Bool) {
        guard let rule = store.configuration.browserRules.first(where: {
            $0.browserBundleID == bundleID && $0.enabled
        }) else { return }
        let target = InputSourceID(composite: rule.inputSourceID)

        if isAddressBar {
            guard target != InputSourceRegistry.current() else { return }
            if browserRuleSuspendedSource == nil {
                browserRuleSuspendedSource = InputSourceRegistry.current()
            }
            InputSourceRegistry.select(target)
        } else if rule.restoreKeyboard, let saved = browserRuleSuspendedSource {
            InputSourceRegistry.select(saved)
            browserRuleSuspendedSource = nil
        }
    }
}

/// One-shot command line interface.
///
/// The menu bar app has no settings window, so configuration is driven from
/// the command line: easier to script, and it keeps the UI down to the one
/// thing that genuinely needs a menu.
enum CLI {
    static func run(_ arguments: [String]) -> Int32 {
        guard let command = arguments.first else { return 0 }
        let store = RuleStore.shared
        switch command {
        case "--current":
            print(InputSourceRegistry.current()?.composite ?? "<none>")
            return 0

        case "--list-sources":
            for source in InputSourceRegistry.availableSources() {
                let mark = source.id == InputSourceRegistry.current() ? "*" : " "
                print("\(mark) \(source.id.composite)\t\(source.displayName)")
            }
            return 0

        case "--switch":
            guard arguments.count >= 2 else { return usage() }
            let target = InputSourceID(composite: InputSourceRegistry.normalize(arguments[1]))
            let ok = InputSourceRegistry.select(target)
            print(ok ? "switched to \(target.composite)" : "failed to switch to \(target.composite)")
            return ok ? 0 : 1

        case "--list-rules":
            for rule in store.configuration.appRules {
                print("\(rule.bundleID)\t\(rule.inputSourceID)\trestore=\(rule.restoreKeyboard)")
            }
            for hotkey in store.configuration.hotkeys {
                print("hotkey\t\(hotkey.id.uuidString)\tkey=\(hotkey.keyCode) mod=\(hotkey.modifiers)\t\(hotkey.inputSourceIDs.joined(separator: ","))")
            }
            for binding in store.configuration.singleModifierBindings {
                print("modifier\t\(binding.modifier.rawValue)\t\(binding.trigger.rawValue)\t\(binding.inputSourceID)")
            }
            for rule in store.configuration.browserRules {
                print("browser\t\(rule.browserBundleID)\t\(rule.inputSourceID)")
            }
            if let fallback = store.configuration.defaultInputSourceID {
                print("default\t\(fallback)")
            }
            return 0

        case "--set-rule":
            // --set-rule <bundleID> <sourceID> [--restore | --no-restore]
            guard arguments.count >= 3 else { return usage() }
            let bundleID = arguments[1]
            let source = InputSourceRegistry.normalize(arguments[2])
            let existing = store.configuration.rule(for: bundleID)
            // Without an explicit flag the existing setting is kept: the flag
            // is not always passed, and dropping it silently would change the
            // behaviour of a rule the user set up earlier.
            let restore: Bool
            if arguments.contains("--restore") {
                restore = true
            } else if arguments.contains("--no-restore") {
                restore = false
            } else {
                restore = existing?.restoreKeyboard ?? false
            }
            store.setAppRule(AppRule(bundleID: bundleID, bundleName: displayName(for: bundleID),
                                     inputSourceID: source, restoreKeyboard: restore))
            print("rule set: \(bundleID) -> \(source) restore=\(restore)")
            return 0

        case "--remove-rule":
            guard arguments.count >= 2 else { return usage() }
            store.removeAppRule(bundleID: arguments[1])
            print("rule removed: \(arguments[1])")
            return 0

        case "--set-browser-rule":
            guard arguments.count >= 3 else { return usage() }
            let source = InputSourceRegistry.normalize(arguments[2])
            store.setBrowserRule(BrowserRule(browserBundleID: arguments[1], inputSourceID: source))
            print("browser rule set: \(arguments[1]) -> \(source)")
            return 0

        case "--set-default-source":
            guard arguments.count >= 2 else { return usage() }
            let source = InputSourceRegistry.normalize(arguments[1])
            store.setDefaultInputSource(source)
            print("default source set: \(source)")
            return 0

        case "--clear-default-source":
            store.setDefaultInputSource(nil)
            print("default source cleared")
            return 0

        case "--add-hotkey":
            // --add-hotkey <keyCode> <modifiers> <source>[,<source>...]
            guard arguments.count >= 4 else { return usage() }
            guard let keyCode = UInt16(arguments[1]), let modifiers = UInt32(arguments[2]) else {
                return usage()
            }
            let sources = arguments[3].split(separator: ",").map {
                InputSourceRegistry.normalize(String($0))
            }
            // Carbon allows only one hotkey per key and modifier combination,
            // so a second one would be dropped with `eventHotKeyExistsErr`.
            // The existing binding is updated instead of adding a duplicate.
            let existing = store.configuration.hotkeys.first {
                $0.keyCode == keyCode && $0.modifiers == modifiers
            }
            let binding = HotkeyBinding(
                id: existing?.id ?? UUID(),
                keyCode: keyCode,
                modifiers: modifiers,
                inputSourceIDs: sources
            )
            let conflicts = HotkeyManager.conflicts(with: binding, in: store.configuration.hotkeys)
            if !conflicts.isEmpty {
                print("error: key=\(keyCode) mod=\(modifiers) is already used by another hotkey")
                return 1
            }
            store.setHotkey(binding)
            print("hotkey set: id=\(binding.id.uuidString) key=\(keyCode) mod=\(modifiers) sources=\(sources.joined(separator: ","))")
            return 0

        case "--remove-hotkey":
            guard arguments.count >= 2, let uuid = UUID(uuidString: arguments[1]) else { return usage() }
            store.removeHotkey(id: uuid)
            print("hotkey removed: \(uuid.uuidString)")
            return 0

        case "--add-single-modifier":
            // --add-single-modifier <option|shift|control|command> <sourceID> [singlePress|doublePress]
            guard arguments.count >= 3,
                  let modifier = ModifierKey.parse(arguments[1]) else { return usage() }
            let trigger = arguments.count >= 4
                ? (SingleModifierTrigger(rawValue: arguments[3]) ?? .singlePress)
                : .singlePress
            let source = InputSourceRegistry.normalize(arguments[2])
            store.update { config in
                let binding = SingleModifierBinding(modifier: modifier, trigger: trigger,
                                                    inputSourceID: source)
                config.singleModifierBindings.removeAll { $0.modifier == modifier }
                config.singleModifierBindings.append(binding)
            }
            print("single modifier set: \(modifier.rawValue) -> \(source) (\(trigger.rawValue))")
            return 0

        case "--remove-single-modifier":
            guard arguments.count >= 2,
                  let modifier = ModifierKey.parse(arguments[1]) else { return usage() }
            store.update { config in
                config.singleModifierBindings.removeAll { $0.modifier == modifier }
            }
            print("single modifier removed: \(modifier.rawValue)")
            return 0

        case "--import-input-source-pro":
            let path = arguments.count >= 2 ? arguments[1] : ISPImporter.defaultStorePath
            let result = ISPImporter.importInto(store: store, from: path)
            for rule in result.imported {
                print("imported \(rule.bundleID) -> \(rule.inputSourceID)")
            }
            for note in result.skipped { print("skipped: \(note)") }
            print("imported \(result.imported.count) rule(s)")
            // Nothing imported and something went wrong: say so.
            return result.imported.isEmpty && !result.skipped.isEmpty ? 1 : 0

        case "--launch-at-login":
            guard arguments.count >= 2 else { return usage() }
            let enabled = parseToggle(arguments[1])
            print(LoginItem.set(enabled))
            return 0

        case "--help", "-h":
            return usage()

        default:
            return usage()
        }
    }

    /// Read an on/off argument, case insensitively.
    ///
    /// "ON" used to be read as "off", which silently removed the login item.
    static func parseToggle(_ argument: String) -> Bool {
        switch argument.lowercased() {
        case "off", "no", "false", "0", "disable", "disabled": return false
        default: return true
        }
    }

    /// The app's display name for a bundle identifier.
    ///
    /// Rules can be set for an app that is not frontmost, so the name is
    /// looked up from the bundle rather than taken from the frontmost app.
    private static func displayName(for bundleID: String) -> String {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier == bundleID {
            return frontmost.localizedName ?? bundleID
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return name
        }
        return bundleID
    }

    private static func usage() -> Int32 {
        let text = """
        input-smarter — 按应用自动切换输入法

          --current                     显示当前输入法
          --list-sources                列出可用输入法
          --switch <sourceID>           切换到指定输入法
          --list-rules                  列出已配置的规则
          --set-rule <bundleID> <sourceID> [--restore|--no-restore]
                                      为应用固定输入法（不带参数时保留原来的设置）
          --remove-rule <bundleID>      取消应用的固定输入法
          --set-browser-rule <bundleID> <sourceID>
                                      为浏览器地址栏固定输入法
          --set-default-source <sourceID>
                                      设置没有规则时使用的默认输入法
          --clear-default-source        取消默认输入法
          --add-hotkey <keyCode> <modifiers> <src1,src2,...>
                                      注册热键（modifiers 为 Carbon 位掩码）；键位组合
                                      已存在时更新原来的热键
          --remove-hotkey <uuid>        删除热键（uuid 见 --list-rules）
          --import-input-source-pro [db] 从 Input Source Pro 的数据库导入规则
          --launch-at-login <on|off>     设置/取消开机自启
          --add-single-modifier <option|shift|control|command> <sourceID> [singlePress|doublePress]
                                      用修饰键点按切换输入法
          --remove-single-modifier <modifier>  取消修饰键切换

        不带参数启动则进入菜单栏常驻模式。
        """
        print(text)
        return 2
    }
}

/// Keeps a second copy of the app from fighting over the input source.
///
/// The LaunchAgent starts the app on its own, so launching it by hand while
/// the agent is loaded used to leave two processes switching the input source
/// behind each other's back.
enum SingleInstance {
    static func anotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != current }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if !arguments.isEmpty {
    exit(CLI.run(arguments))
}

if SingleInstance.anotherInstanceRunning() {
    Log.error("another instance is already running; exiting")
    FileHandle.standardError.write(Data("input-smarter is already running\n".utf8))
    exit(0)
}

let application = NSApplication.shared
let controller = AppController()
application.setActivationPolicy(.accessory)
controller.start()
application.run()
