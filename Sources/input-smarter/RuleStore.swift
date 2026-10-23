import Foundation

/// Persists the configuration as JSON under Application Support.
///
/// JSON rather than Core Data: the configuration is a handful of records read
/// on every app switch, so there is nothing a query layer would buy, and a
/// plain file keeps the app inspectable and trivially backed up.
final class RuleStore {
    static let shared = RuleStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.input-smarter.rulestore")
    private var _configuration = Configuration()
    private var loadedModificationDate: Date?
    private let notification = Notification.Name("com.input-smarter.configurationChanged")
    /// Last decode failure, so the same problem is not logged on every read.
    private var lastReportedError: String?

    /// The current configuration, re-read from disk when another process (the
    /// CLI) has changed the file.
    var configuration: Configuration {
        queue.sync {
            reloadIfChanged()
            return _configuration
        }
    }

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = Self.defaultDirectory
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("config.json")
        }
        load()
    }

    /// Where the configuration lives.
    ///
    /// `INPUT_SMARTER_CONFIG_DIR` overrides it, which is what makes it
    /// possible to try the app out with a separate configuration.
    private static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["INPUT_SMARTER_CONFIG_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("input-smarter", isDirectory: true)
    }

    /// Fired after any mutation so watchers can re-read the rules.
    var onChange: Notification.Name { notification }

    /// The file the configuration lives in.
    var path: String { fileURL.path }

    // MARK: - Loading

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loadedModificationDate = modificationDate()
            return
        }
        guard let config = decodeFile(at: fileURL) else {
            // Keep the modification date unset so the next read retries: the
            // file may be repaired (or replaced) in the meantime.
            loadedModificationDate = nil
            _configuration = decodeBackup() ?? Configuration()
            return
        }
        _configuration = config
        loadedModificationDate = modificationDate()
    }

    /// Re-read the file when it changed underneath us (the CLI writes it).
    private func reloadIfChanged() {
        let current = modificationDate()
        guard current != loadedModificationDate else { return }
        guard let config = decodeFile(at: fileURL) else {
            // Do not advance the modification date: a file we cannot decode
            // must be retried, otherwise one bad write disables the file for
            // the rest of the session.
            report(error: "cannot decode \(fileURL.path); keeping the previous configuration")
            _configuration = decodeBackup() ?? _configuration
            return
        }
        loadedModificationDate = current
        _configuration = config
    }

    /// Decode a configuration file, logging why it failed.
    private func decodeFile(at url: URL) -> Configuration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Configuration.self, from: data)
        } catch {
            report(error: "cannot decode \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// The last known good copy, used when the live file is unreadable.
    private func decodeBackup() -> Configuration? {
        let backup = fileURL.appendingPathExtension("bak")
        guard FileManager.default.fileExists(atPath: backup.path) else { return nil }
        guard let config = decodeFile(at: backup) else { return nil }
        report(error: "recovered the configuration from \(backup.path)")
        return config
    }

    private func modificationDate() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attributes?[.modificationDate] as? Date
    }

    // MARK: - Saving

    private func save(_ config: Configuration) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else {
            report(error: "cannot encode the configuration")
            return
        }
        do {
            // Keep the previous contents: it is the only way back if the new
            // file turns out to be unreadable.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backup = fileURL.appendingPathExtension("bak")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            report(error: "cannot write \(fileURL.path): \(error.localizedDescription)")
        }
    }

    /// Replace the whole configuration.
    ///
    /// The file is re-read first: the CLI runs in its own process, so the
    /// in-memory copy can be older than the file — writing it back would
    /// silently drop whatever the CLI changed in the meantime.
    func update(_ mutate: (inout Configuration) -> Void) {
        queue.sync {
            reloadIfChanged()
            var config = _configuration
            mutate(&config)
            _configuration = config
            // Saved inside the lock, so two updates in this process cannot
            // reach the disk out of order.
            save(config)
        }
        // Posted through the distributed centre as well: the CLI runs in its
        // own process, and a plain NotificationCenter post would never reach
        // the menu bar app.
        NotificationCenter.default.post(name: notification, object: nil)
        DistributedNotificationCenter.default().post(name: notification, object: nil, userInfo: nil)
    }

    // MARK: - Convenience mutators

    func setAppRule(_ rule: AppRule) {
        update { config in
            if let index = config.appRules.firstIndex(where: { $0.bundleID == rule.bundleID }) {
                config.appRules[index] = rule
            } else {
                config.appRules.append(rule)
            }
        }
    }

    func removeAppRule(bundleID: String) {
        update { config in
            config.appRules.removeAll { $0.bundleID == bundleID }
        }
    }

    func setHotkey(_ hotkey: HotkeyBinding) {
        update { config in
            if let index = config.hotkeys.firstIndex(where: { $0.id == hotkey.id }) {
                config.hotkeys[index] = hotkey
            } else {
                config.hotkeys.append(hotkey)
            }
        }
    }

    func removeHotkey(id: UUID) {
        update { config in
            config.hotkeys.removeAll { $0.id == id }
        }
    }

    func setBrowserRule(_ rule: BrowserRule) {
        update { config in
            if let index = config.browserRules.firstIndex(where: { $0.browserBundleID == rule.browserBundleID }) {
                config.browserRules[index] = rule
            } else {
                config.browserRules.append(rule)
            }
        }
    }

    func setDefaultInputSource(_ inputSourceID: String?) {
        update { config in
            config.defaultInputSourceID = inputSourceID
        }
    }

    // MARK: - Diagnostics

    private func report(error message: String) {
        guard message != lastReportedError else { return }
        lastReportedError = message
        Log.error(message)
    }
}
