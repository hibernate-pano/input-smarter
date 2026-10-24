import AppKit
import Foundation

/// An application installed on this Mac.
struct InstalledApp: Identifiable, Hashable {
    /// Stable key of a rule.
    let bundleID: String
    /// What the user sees.
    let displayName: String
    /// Where the bundle lives.
    let url: URL

    var id: String { bundleID }
}

/// Finds the applications installed on this Mac.
///
/// The settings window lists them so a rule can be created for an app before
/// the user ever opens it — the menu bar can only bind the app that is
/// frontmost right now.
enum AppCatalog {
    /// The folders applications live in.
    ///
    /// `Utilities` is scanned as well: it holds apps of its own (Terminal,
    /// Activity Monitor).
    static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// Every app bundle in the given folders.
    ///
    /// Bundles without a bundle identifier are skipped: a rule is keyed by
    /// the bundle identifier, so an app without one cannot be bound.
    static func installedApps(in directories: [URL]) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        for directory in directories {
            for folder in [directory, directory.appendingPathComponent("Utilities", isDirectory: true)] {
                let entries = (try? FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
                for url in entries {
                    guard url.pathExtension == "app" else { continue }
                    guard let app = app(at: url) else { continue }
                    // The same app can be in more than one folder; it may only
                    // be listed once.
                    guard seen.insert(app.bundleID).inserted else { continue }
                    apps.append(app)
                }
            }
        }
        // The list is read by looking for a name, so it has to be in a stable
        // order.
        return apps.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func app(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier,
              !bundleID.isEmpty else { return nil }
        let name = firstNonEmpty(
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            url.deletingPathExtension().lastPathComponent
        )
        return InstalledApp(bundleID: bundleID, displayName: name, url: url)
    }

    /// The app of a bundle identifier, wherever it is installed.
    ///
    /// The scan only looks in the folders people put apps in. An app that
    /// lives somewhere else — the Finder, for one — is found through Launch
    /// Services.
    static func app(withBundleID bundleID: String) -> InstalledApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return app(at: url)
    }

    /// One list of the scanned apps and the ones found elsewhere.
    ///
    /// An app that is in both lists is only in the list once; the scanned one
    /// wins, because the scan knows where it came from.
    static func merge(_ scanned: [InstalledApp], _ resolved: [InstalledApp]) -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for app in scanned + resolved {
            guard seen.insert(app.bundleID).inserted else { continue }
            apps.append(app)
        }
        return apps.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String {
        for candidate in candidates {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return ""
    }
}
