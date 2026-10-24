import Foundation
import Testing

@testable import input_smarter

private func installed(_ bundleID: String, _ name: String) -> InstalledApp {
    InstalledApp(
        bundleID: bundleID,
        displayName: name,
        url: URL(fileURLWithPath: "/Applications/\(name).app")
    )
}

private func rule(_ bundleID: String, _ name: String, source: String = "com.apple.keylayout.ABC") -> AppRule {
    AppRule(bundleID: bundleID, bundleName: name, inputSourceID: source)
}

/// The window only lists the apps that have a rule. Listing every installed
/// app is noise: the user configures a handful of them.
@Test func onlyConfiguredAppsAreListed() {
    let rows = AppList.configuredRows(
        rules: [rule("com.example.zulu", "Zulu")],
        installed: [installed("com.example.alpha", "Alpha"), installed("com.example.zulu", "Zulu")]
    )

    #expect(rows.count == 1)
    #expect(rows[0].bundleID == "com.example.zulu")
}

/// A rule for an app that is not installed must not disappear: the user
/// configured it, and it is still a rule.
@Test func aRuleForAnAppThatIsNotInstalledIsStillListed() {
    let rows = AppList.configuredRows(
        rules: [rule("com.removed.app", "已删除的 App")],
        installed: [installed("com.example.alpha", "Alpha")]
    )

    #expect(rows.count == 1)
    let missing = rows.first { $0.bundleID == "com.removed.app" }
    #expect(missing != nil)
    #expect(missing?.name == "已删除的 App")
    #expect(missing?.isInstalled == false)
    #expect(missing?.isConfigured == true)
}

/// The row has to say which input source the app is bound to.
@Test func aRowCarriesTheBoundInputSource() {
    let rows = AppList.configuredRows(
        rules: [rule("com.example.alpha", "Alpha", source: "com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin")],
        installed: [installed("com.example.alpha", "Alpha")]
    )

    #expect(rows.count == 1)
    #expect(rows[0].boundSourceID == "com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin")
}

/// The name of the rule is the localized name the user knows the app by —
/// the system calls the Finder "访达", not "Finder".
@Test func aConfiguredAppIsShownUnderTheNameOfItsRule() {
    let rows = AppList.configuredRows(
        rules: [rule("com.apple.finder", "访达")],
        installed: [installed("com.apple.finder", "Finder")]
    )

    #expect(rows[0].name == "访达")
}

/// Some rules carry the file name of the app, with the suffix.
@Test func theAppSuffixIsNotPartOfTheName() {
    let rows = AppList.configuredRows(
        rules: [rule("com.apple.Terminal", "终端.app")],
        installed: []
    )

    #expect(rows[0].name == "终端")
}

/// The apps that can still be added are the installed ones without a rule.
@Test func theCandidatesAreTheAppsWithoutARule() {
    let candidates = AppList.candidates(
        installed: [
            installed("com.example.alpha", "Alpha"),
            installed("com.example.beta", "Beta"),
            installed("com.example.zulu", "Zulu"),
        ],
        rules: [rule("com.example.beta", "Beta")]
    )

    #expect(candidates.map(\.bundleID) == ["com.example.alpha", "com.example.zulu"])
}

/// An app that is already configured is not offered again.
@Test func anAppThatHasARuleIsNotACandidate() {
    let candidates = AppList.candidates(
        installed: [installed("com.example.alpha", "Alpha")],
        rules: [rule("com.example.alpha", "Alpha")]
    )

    #expect(candidates.isEmpty)
}

/// The search box is how an app is looked up in a list of hundreds.
@Test func theSearchMatchesTheName() {
    let candidates = AppList.candidates(
        installed: [installed("com.example.chrome", "Google Chrome"), installed("com.example.notes", "备忘录")],
        rules: []
    )

    let found = AppList.filter(candidates, by: "chrome")

    #expect(found.map(\.bundleID) == ["com.example.chrome"])
}

/// Power users know the bundle identifier, so it is searchable too.
@Test func theSearchAlsoMatchesTheBundleIdentifier() {
    let candidates = AppList.candidates(
        installed: [installed("com.example.chrome", "Google Chrome")],
        rules: []
    )

    let found = AppList.filter(candidates, by: "com.example")

    #expect(found.map(\.bundleID) == ["com.example.chrome"])
}

/// A Chinese app name has to be searchable by the characters the user types.
@Test func theSearchMatchesANonLatinName() {
    let candidates = AppList.candidates(
        installed: [installed("com.tencent.xinWeChat", "微信")],
        rules: []
    )

    #expect(AppList.filter(candidates, by: "微").map(\.bundleID) == ["com.tencent.xinWeChat"])
}

/// An empty search shows everything.
@Test func anEmptySearchKeepsEverything() {
    let candidates = AppList.candidates(
        installed: [installed("com.example.alpha", "Alpha"), installed("com.example.beta", "Beta")],
        rules: []
    )

    #expect(AppList.filter(candidates, by: "").count == 2)
    #expect(AppList.filter(candidates, by: "   ").count == 2)
}
