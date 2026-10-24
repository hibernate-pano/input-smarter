import Foundation

/// One row of the app list.
struct AppListRow: Identifiable, Hashable {
    let bundleID: String
    let name: String
    /// Composite id of the input source the app is bound to; nil when it is
    /// not bound to anything.
    let boundSourceID: String?
    /// False when the rule points at an app that is not installed.
    let isInstalled: Bool
    /// Where the app bundle lives; nil when it is not installed.
    let url: URL?

    var id: String { bundleID }
    var isConfigured: Bool { boundSourceID != nil }
}

/// The app list of the settings window.
///
/// The window lists the apps that have a rule. The user configures a handful
/// of them; listing every installed app is noise. The apps that can still be
/// added come from the installed ones.
enum AppList {
    /// The rows of the window: one per rule.
    ///
    /// A rule for an app that is not installed stays in the list — it is
    /// still a rule, and the user has to be able to remove it.
    static func configuredRows(rules: [AppRule], installed: [InstalledApp]) -> [AppListRow] {
        var installedByID: [String: InstalledApp] = [:]
        for app in installed {
            if installedByID[app.bundleID] == nil {
                installedByID[app.bundleID] = app
            }
        }

        return rules.map { rule in
            let app = installedByID[rule.bundleID]
            return AppListRow(
                bundleID: rule.bundleID,
                // The name of the rule is the localized name the user knows
                // the app by — the system calls the Finder "访达", not
                // "Finder".
                name: displayName(of: rule.bundleName) ?? app?.displayName ?? rule.bundleID,
                boundSourceID: rule.inputSourceID,
                isInstalled: app != nil,
                url: app?.url
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The installed apps that have no rule yet.
    static func candidates(installed: [InstalledApp], rules: [AppRule]) -> [InstalledApp] {
        let configured = Set(rules.map(\.bundleID))
        return installed
            .filter { !configured.contains($0.bundleID) }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
    }

    /// Narrow the apps down to what the user typed.
    ///
    /// Both the name and the bundle identifier are searched: the name is
    /// what most people know, the identifier is what power users know.
    static func filter(_ apps: [InstalledApp], by search: String) -> [InstalledApp] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return apps }
        return apps.filter {
            $0.displayName.lowercased().contains(needle) || $0.bundleID.lowercased().contains(needle)
        }
    }

    /// The name of an app, without the file suffix.
    ///
    /// Some rules carry the name of the bundle file, with its suffix.
    private static func displayName(of name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix(".app") {
            return String(trimmed.dropLast(4))
        }
        return trimmed
    }
}
