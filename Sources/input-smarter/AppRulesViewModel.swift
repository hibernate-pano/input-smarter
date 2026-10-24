import AppKit
import Combine
import Foundation

/// Drives the app list of the settings window.
///
/// The window lists the apps that have a rule. The apps that can still be
/// added are the candidates: the installed ones without a rule.
@MainActor
final class AppRulesViewModel: ObservableObject {
    /// The search text of the app picker.
    @Published var searchText: String = ""
    /// True while the app picker is open.
    @Published var isPicking: Bool = false
    /// The apps that have a rule; one row each.
    @Published private(set) var rows: [AppListRow] = []
    /// The installed apps that have no rule yet.
    @Published private(set) var candidates: [InstalledApp] = []
    /// True while the installed apps are still being read from disk.
    @Published private(set) var isLoading: Bool = false
    /// The input sources the user can pick from.
    @Published var sources: [InputSourceInfo]
    /// The icons of the apps, filled in as the rows come into view.
    @Published private(set) var icons: [String: NSImage] = [:]
    /// The input source that is in use right now; the source a newly added app
    /// is bound to.
    @Published var currentSourceID: String?

    /// Called after a rule was changed, so the running app can apply it right
    /// away instead of on the next app switch.
    var onRulesChanged: (() -> Void)?

    private let store: RuleStore
    private var installed: [InstalledApp]
    private var iconsInFlight = Set<String>()

    init(store: RuleStore, installed: [InstalledApp], sources: [InputSourceInfo]) {
        self.store = store
        self.installed = installed
        self.sources = sources
        reload()
    }

    /// Hand over the apps that were read from disk.
    func setInstalled(_ apps: [InstalledApp]) {
        installed = apps
        isLoading = false
        reload()
    }

    /// The apps are being read; the list is not complete yet.
    func beginLoading() {
        isLoading = true
    }

    /// Hand over the input sources the user can pick from.
    func setSources(_ sources: [InputSourceInfo]) {
        self.sources = sources
    }

    /// A readable name for the identifier of an input source.
    ///
    /// The composite form is `sourceID::modeID`; the source id alone says
    /// more than the whole thing.
    func shortName(of inputSourceID: String) -> String {
        let source = inputSourceID.split(separator: "::").first.map(String.init)
        return source ?? inputSourceID
    }

    /// The candidates that the search leaves over.
    var visibleCandidates: [InstalledApp] {
        AppList.filter(candidates, by: searchText)
    }

    func reload() {
        let rules = store.configuration.appRules
        rows = AppList.configuredRows(rules: rules, installed: installed)
        candidates = AppList.candidates(installed: installed, rules: rules)
    }

    /// Add an app to the list, bound to an input source.
    ///
    /// Without a source the input source that is in use right now is taken;
    /// without one of those the app is not added at all — a rule without an
    /// input source would do nothing.
    func add(_ app: InstalledApp, to sourceID: String? = nil) {
        guard let source = sourceID ?? currentSourceID, !source.isEmpty else { return }
        store.setAppRule(AppRule(
            bundleID: app.bundleID,
            bundleName: app.displayName,
            inputSourceID: source
        ))
        reload()
        onRulesChanged?()
    }

    /// Bind an app to an input source, or unbind it when the source is nil.
    ///
    /// Unbinding removes the rule: the app goes back to the system's default
    /// and leaves the list, to be added again later if needed.
    func bind(_ row: AppListRow, to sourceID: String?) {
        guard let sourceID, !sourceID.isEmpty else {
            unbind(row)
            return
        }
        // The window cannot show the restore setting, so an existing value is
        // kept instead of being silently dropped.
        let existing = store.configuration.rule(for: row.bundleID)
        store.setAppRule(AppRule(
            bundleID: row.bundleID,
            bundleName: row.name,
            inputSourceID: sourceID,
            restoreKeyboard: existing?.restoreKeyboard ?? false,
            hideIndicator: existing?.hideIndicator ?? false
        ))
        reload()
        onRulesChanged?()
    }

    /// Remove the rule of an app; the app leaves the list.
    func unbind(_ row: AppListRow) {
        store.removeAppRule(bundleID: row.bundleID)
        reload()
        onRulesChanged?()
    }

    /// Switch the input source back to the previous one when the app is left.
    func setRestore(_ row: AppListRow, restore: Bool) {
        guard let existing = store.configuration.rule(for: row.bundleID) else { return }
        store.setAppRule(AppRule(
            bundleID: existing.bundleID,
            bundleName: existing.bundleName,
            inputSourceID: existing.inputSourceID,
            restoreKeyboard: restore,
            hideIndicator: existing.hideIndicator
        ))
        reload()
        onRulesChanged?()
    }

    /// Whether the app's input source is restored when the app is left.
    func restoresOnLeave(_ row: AppListRow) -> Bool {
        store.configuration.rule(for: row.bundleID)?.restoreKeyboard ?? false
    }

    /// Load the icon of an app.
    ///
    /// The icon is read from disk, which is too slow to do while the list is
    /// scrolling, so it is read in the background and only for the rows that
    /// come into view.
    func loadIcon(bundleID: String, url: URL?) {
        guard let url else { return }
        guard icons[bundleID] == nil, !iconsInFlight.contains(bundleID) else { return }
        iconsInFlight.insert(bundleID)
        Task { @MainActor [weak self] in
            let icon = await Self.readIcon(at: url)
            self?.iconsInFlight.remove(bundleID)
            self?.icons[bundleID] = icon.image
        }
    }

    /// Read an icon off the main thread.
    ///
    /// The reads are serialized: `NSWorkspace` is not known to be safe to use
    /// from several threads at once.
    private static func readIcon(at url: URL) async -> IconBox {
        await withCheckedContinuation { continuation in
            iconQueue.async {
                continuation.resume(returning: IconBox(image: NSWorkspace.shared.icon(forFile: url.path)))
            }
        }
    }

    private static let iconQueue = DispatchQueue(label: "com.input-smarter.icons", qos: .userInitiated)
}

/// Carries an icon across an actor boundary.
///
/// `NSImage` is only `Sendable` from macOS 14 on, and the app still runs on
/// macOS 13.
private struct IconBox: @unchecked Sendable {
    let image: NSImage
}
