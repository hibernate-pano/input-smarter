import Foundation
import Testing

@testable import input_smarter

/// Builds a minimal `.app` bundle on disk.
@discardableResult
private func makeApp(
    in directory: URL,
    name: String,
    bundleID: String? = nil,
    displayName: String? = nil
) throws -> URL {
    let url = directory.appendingPathComponent("\(name).app", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var info: [String: Any] = [:]
    if let bundleID { info["CFBundleIdentifier"] = bundleID }
    if let displayName { info["CFBundleDisplayName"] = displayName }
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: url.appendingPathComponent("Info.plist"))
    return url
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("input-smarter-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// The app list is the one part of the settings window that has to work
/// before the user has configured anything, so it is built from the disk.
@Test func theCatalogFindsAppBundles() throws {
    let root = try makeTemporaryDirectory()
    try makeApp(in: root, name: "Alpha", bundleID: "com.example.alpha")

    let apps = AppCatalog.installedApps(in: [root])

    #expect(apps.count == 1)
    #expect(apps.first?.bundleID == "com.example.alpha")
    #expect(apps.first?.displayName == "Alpha")
    #expect(apps.first?.url.lastPathComponent == "Alpha.app")
}

/// Without a bundle identifier there is nothing to key a rule on.
@Test func theCatalogSkipsBundlesWithoutABundleIdentifier() throws {
    let root = try makeTemporaryDirectory()
    try makeApp(in: root, name: "NoID")
    try makeApp(in: root, name: "WithID", bundleID: "com.example.withid")

    let apps = AppCatalog.installedApps(in: [root])

    #expect(apps.map(\.bundleID) == ["com.example.withid"])
}

/// A directory that is not an app bundle, and a file, are not apps.
@Test func theCatalogIgnoresThingsThatAreNotApps() throws {
    let root = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("Folder", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("not an app".utf8).write(to: root.appendingPathComponent("readme.txt"))
    try makeApp(in: root, name: "Real", bundleID: "com.example.real")

    let apps = AppCatalog.installedApps(in: [root])

    #expect(apps.map(\.bundleID) == ["com.example.real"])
}

/// The display name is what the user recognises; the file name is the
/// fallback when the bundle does not name itself.
@Test func theCatalogPrefersTheDisplayNameOverTheFileName() throws {
    let root = try makeTemporaryDirectory()
    try makeApp(in: root, name: "WeChat", bundleID: "com.tencent.xinWeChat", displayName: "微信")
    try makeApp(in: root, name: "Plain", bundleID: "com.example.plain")

    let apps = AppCatalog.installedApps(in: [root])
    let names = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0.displayName) })

    #expect(names["com.tencent.xinWeChat"] == "微信")
    #expect(names["com.example.plain"] == "Plain")
}

/// The `Utilities` folder holds apps of its own (Terminal, Activity Monitor).
@Test func theCatalogAlsoLooksInTheUtilitiesFolder() throws {
    let root = try makeTemporaryDirectory()
    let utilities = root.appendingPathComponent("Utilities", isDirectory: true)
    try FileManager.default.createDirectory(at: utilities, withIntermediateDirectories: true)
    try makeApp(in: utilities, name: "Terminal", bundleID: "com.apple.Terminal")
    try makeApp(in: root, name: "Safari", bundleID: "com.apple.Safari")

    let apps = AppCatalog.installedApps(in: [root])

    #expect(Set(apps.map(\.bundleID)) == ["com.apple.Terminal", "com.apple.Safari"])
}

/// The list is read by looking for a name, so it has to be in a stable order.
@Test func theCatalogSortsAppsByName() throws {
    let root = try makeTemporaryDirectory()
    try makeApp(in: root, name: "Zebra", bundleID: "com.example.zebra")
    try makeApp(in: root, name: "Apple", bundleID: "com.example.apple")
    try makeApp(in: root, name: "Mango", bundleID: "com.example.mango")

    let apps = AppCatalog.installedApps(in: [root])

    #expect(apps.map(\.displayName) == ["Apple", "Mango", "Zebra"])
}

/// The same app can sit in more than one folder; it may only be listed once.
@Test func theCatalogListsAnAppOnlyOnce() throws {
    let root = try makeTemporaryDirectory()
    try makeApp(in: root, name: "Safari", bundleID: "com.apple.Safari")
    try makeApp(in: root, name: "Safari Copy", bundleID: "com.apple.Safari")

    let apps = AppCatalog.installedApps(in: [root])

    #expect(apps.count == 1)
}

/// An app that is not in the folders people put apps in — the Finder, for
/// one — is still found, through Launch Services.
@Test func anAppOutsideTheScannedFoldersIsFoundByItsBundleIdentifier() {
    let app = AppCatalog.app(withBundleID: "com.apple.finder")

    #expect(app?.bundleID == "com.apple.finder")
    #expect(app?.displayName == "Finder")
}

/// A bundle identifier that belongs to no app has no app.
@Test func anUnknownBundleIdentifierHasNoApp() {
    #expect(AppCatalog.app(withBundleID: "com.example.not.installed") == nil)
}

/// The scanned apps and the ones found elsewhere are one list.
@Test func theScannedAndTheResolvedAppsAreMerged() {
    let scanned = [
        InstalledApp(bundleID: "com.example.alpha", displayName: "Alpha", url: URL(fileURLWithPath: "/Applications/Alpha.app")),
    ]
    let resolved = [
        InstalledApp(bundleID: "com.example.alpha", displayName: "Alpha", url: URL(fileURLWithPath: "/elsewhere/Alpha.app")),
        InstalledApp(bundleID: "com.example.beta", displayName: "Beta", url: URL(fileURLWithPath: "/elsewhere/Beta.app")),
    ]

    let merged = AppCatalog.merge(scanned, resolved)

    #expect(merged.map(\.bundleID) == ["com.example.alpha", "com.example.beta"])
}
