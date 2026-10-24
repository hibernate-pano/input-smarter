import Foundation
import Testing

@testable import input_smarter

@MainActor
private func makeStore() -> RuleStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("input-smarter-tests")
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    return RuleStore(fileURL: url)
}

private func source(_ name: String) -> InputSourceInfo {
    InputSourceInfo(
        id: InputSourceID(sourceID: "com.example.\(name)", modeID: "com.example.\(name)"),
        name: name,
        bundleID: "",
        isASCIICapable: false,
        isKeyboardLayout: false
    )
}

private func installed(_ bundleID: String, _ name: String) -> InstalledApp {
    InstalledApp(
        bundleID: bundleID,
        displayName: name,
        url: URL(fileURLWithPath: "/Applications/\(name).app")
    )
}

@MainActor
private func makeViewModel(
    store: RuleStore,
    installed: [InstalledApp] = [installed("com.example.alpha", "Alpha")]
) -> AppRulesViewModel {
    AppRulesViewModel(
        store: store,
        installed: installed,
        sources: [source("拼音"), source("ABC")]
    )
}

/// Adding an app has to end up in the configuration file.
@Test @MainActor func addingAnAppWritesARule() {
    let store = makeStore()
    let model = makeViewModel(store: store)

    model.add(installed("com.example.beta", "Beta"), to: "com.example.拼音::com.example.拼音")

    let rule = store.configuration.rule(for: "com.example.beta")
    #expect(rule != nil)
    #expect(rule?.inputSourceID == "com.example.拼音::com.example.拼音")
    #expect(rule?.bundleName == "Beta")
}

/// The added app has to show up in the list.
@Test @MainActor func anAddedAppShowsUpInTheList() {
    let store = makeStore()
    let model = makeViewModel(store: store)

    model.add(installed("com.example.beta", "Beta"), to: "com.example.拼音::com.example.拼音")

    #expect(model.rows.map(\.bundleID) == ["com.example.beta"])
    #expect(model.rows[0].boundSourceID == "com.example.拼音::com.example.拼音")
}

/// An app that is already configured is not offered again.
@Test @MainActor func anAppThatIsConfiguredIsNotACandidate() {
    let store = makeStore()
    let model = makeViewModel(store: store)

    model.add(installed("com.example.alpha", "Alpha"), to: "com.example.ABC::com.example.ABC")

    #expect(model.candidates.isEmpty)
}

/// Changing the input source of an app has to end up in the configuration.
@Test @MainActor func bindingAnAppWritesARule() {
    let store = makeStore()
    store.setAppRule(AppRule(
        bundleID: "com.example.alpha",
        bundleName: "Alpha",
        inputSourceID: "com.example.old::com.example.old"
    ))
    let model = makeViewModel(store: store)

    model.bind(model.rows[0], to: "com.example.拼音::com.example.拼音")

    let rule = store.configuration.rule(for: "com.example.alpha")
    #expect(rule != nil)
    #expect(rule?.inputSourceID == "com.example.拼音::com.example.拼音")
    #expect(rule?.bundleName == "Alpha")
}

/// The window cannot show the restore setting, so it must not silently drop
/// it when the input source is changed.
@Test @MainActor func bindingKeepsTheRestoreSettingOfTheExistingRule() {
    let store = makeStore()
    store.setAppRule(AppRule(
        bundleID: "com.example.alpha",
        bundleName: "Alpha",
        inputSourceID: "com.example.old::com.example.old",
        restoreKeyboard: true
    ))
    let model = makeViewModel(store: store)

    model.bind(model.rows[0], to: "com.example.拼音::com.example.拼音")

    #expect(store.configuration.rule(for: "com.example.alpha")?.inputSourceID == "com.example.拼音::com.example.拼音")
    #expect(store.configuration.rule(for: "com.example.alpha")?.restoreKeyboard == true)
}

/// Going back to the default removes the rule — and the row with it.
@Test @MainActor func unbindingRemovesTheRuleAndTheRow() {
    let store = makeStore()
    store.setAppRule(AppRule(
        bundleID: "com.example.alpha",
        bundleName: "Alpha",
        inputSourceID: "com.example.old::com.example.old"
    ))
    let model = makeViewModel(store: store)

    model.bind(model.rows[0], to: nil)

    #expect(store.configuration.rule(for: "com.example.alpha") == nil)
    #expect(model.rows.isEmpty)
}

/// The row has to show what it was just bound to.
@Test @MainActor func theRowShowsTheSourceItWasBoundTo() {
    let store = makeStore()
    store.setAppRule(AppRule(
        bundleID: "com.example.alpha",
        bundleName: "Alpha",
        inputSourceID: "com.example.old::com.example.old"
    ))
    let model = makeViewModel(store: store)

    model.bind(model.rows[0], to: "com.example.拼音::com.example.拼音")

    #expect(model.rows[0].boundSourceID == "com.example.拼音::com.example.拼音")
    #expect(model.rows[0].isConfigured)
}

/// The search box of the app picker narrows what can be added.
@Test @MainActor func theSearchNarrowsTheCandidates() {
    let store = makeStore()
    let model = makeViewModel(
        store: store,
        installed: [installed("com.example.alpha", "Alpha"), installed("com.example.chrome", "Chrome")]
    )

    model.searchText = "chr"

    #expect(model.visibleCandidates.map(\.bundleID) == ["com.example.chrome"])
}
