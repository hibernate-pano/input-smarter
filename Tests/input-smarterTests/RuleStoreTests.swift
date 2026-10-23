import Foundation
import Testing

@testable import input_smarter

/// A temporary configuration file.
private func makeStore() -> (RuleStore, URL) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("input-smarter-tests")
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    return (RuleStore(fileURL: url), url)
}

private func write(_ json: String, to url: URL) {
    try? Data(json.utf8).write(to: url, options: .atomic)
}

/// A configuration that predates some of the fields must still load.
///
/// The synthesized `Decodable` conformance ignores the property defaults and
/// throws for a missing key, which used to turn one outdated file into an
/// empty configuration.
@Test func aConfigurationWithMissingKeysStillLoads() throws {
    let (store, url) = makeStore()
    write("""
    {
      "appRules": [
        { "bundleID": "com.apple.finder", "bundleName": "访达", "inputSourceID": "com.apple.keylayout.ABC" }
      ]
    }
    """, to: url)

    let reloaded = RuleStore(fileURL: url)
    #expect(reloaded.configuration.appRules.count == 1)
    #expect(reloaded.configuration.appRules.first?.bundleID == "com.apple.finder")
    #expect(reloaded.configuration.appRules.first?.restoreKeyboard == false)
    #expect(reloaded.configuration.hotkeys.isEmpty)
    #expect(reloaded.configuration.browserRules.isEmpty)
    store.configuration
}

/// A rule written by an older version has no `hideIndicator`.
@Test func anOldRuleStillDecodes() throws {
    let (store, url) = makeStore()
    write("""
    {
      "appRules": [
        {
          "bundleID": "com.google.Chrome",
          "bundleName": "Chrome",
          "inputSourceID": "com.apple.keylayout.ABC",
          "restoreKeyboard": true
        }
      ],
      "hotkeys": [],
      "singleModifierBindings": [],
      "browserRules": []
    }
    """, to: url)

    let reloaded = RuleStore(fileURL: url)
    let rule = try #require(reloaded.configuration.appRules.first)
    #expect(rule.restoreKeyboard == true)
    #expect(rule.hideIndicator == false)
    store.configuration
}

/// The CLI runs in its own process: the app must not write back a stale
/// in-memory copy over what the CLI just wrote.
@Test func updateReadsTheFileBeforeWriting() throws {
    let (store, url) = makeStore()
    write("""
    {
      "appRules": [
        { "bundleID": "com.google.Chrome", "bundleName": "Chrome", "inputSourceID": "com.apple.keylayout.ABC", "restoreKeyboard": false, "hideIndicator": false }
      ],
      "hotkeys": [],
      "singleModifierBindings": [],
      "browserRules": []
    }
    """, to: url)

    let reloaded = RuleStore(fileURL: url)
    reloaded.update { config in
        config.appRules.append(AppRule(
            bundleID: "com.microsoft.VSCode",
            bundleName: "VSCode",
            inputSourceID: "com.apple.keylayout.ABC"
        ))
    }

    let bundleIDs = reloaded.configuration.appRules.map(\.bundleID)
    #expect(bundleIDs.contains("com.google.Chrome"), "the CLI's rule was dropped")
    #expect(bundleIDs.contains("com.microsoft.VSCode"))
}

/// A file that cannot be decoded must not empty the configuration, and the
/// next write must not throw the user's rules away.
@Test func aBrokenFileKeepsThePreviousConfiguration() throws {
    let (store, url) = makeStore()
    write("""
    {
      "appRules": [
        { "bundleID": "com.apple.finder", "bundleName": "访达", "inputSourceID": "com.apple.keylayout.ABC", "restoreKeyboard": false, "hideIndicator": false }
      ],
      "hotkeys": [],
      "singleModifierBindings": [],
      "browserRules": []
    }
    """, to: url)

    let reloaded = RuleStore(fileURL: url)
    #expect(reloaded.configuration.appRules.count == 1)

    write("{ this is not json", to: url)
    // The file changed, so the store tries to read it again — and fails.
    #expect(reloaded.configuration.appRules.count == 1, "the broken file emptied the configuration")
    store.configuration
}

/// The written file keeps the previous contents as a backup.
@Test func savingKeepsABackup() throws {
    let (store, url) = makeStore()
    store.update { config in
        config.appRules.append(AppRule(
            bundleID: "com.apple.finder",
            bundleName: "访达",
            inputSourceID: "com.apple.keylayout.ABC"
        ))
    }
    store.update { config in
        config.appRules.append(AppRule(
            bundleID: "com.apple.Terminal",
            bundleName: "终端",
            inputSourceID: "com.apple.keylayout.ABC"
        ))
    }

    let backup = url.appendingPathExtension("bak")
    #expect(FileManager.default.fileExists(atPath: backup.path))
    store.configuration
}
