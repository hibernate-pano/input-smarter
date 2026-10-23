import AppKit
import Foundation
import Testing

@testable import input_smarter

private func sources() -> [InputSourceInfo] {
    [
        InputSourceInfo(
            id: InputSourceID(sourceID: "com.apple.keylayout.ABC"),
            name: "ABC",
            bundleID: "",
            isASCIICapable: true,
            isKeyboardLayout: true
        ),
        InputSourceInfo(
            id: InputSourceID(
                sourceID: "com.tencent.inputmethod.wetype.pinyin",
                modeID: "com.tencent.inputmethod.wetype.pinyin"
            ),
            name: "拼音",
            bundleID: "",
            isASCIICapable: false,
            isKeyboardLayout: false
        ),
    ]
}

/// The source an app is pinned to has to be marked in the menu, otherwise
/// the menu cannot be read at a glance.
@Test func theBoundSourceIsMarkedInTheBindMenu() {
    let rule = AppRule(
        bundleID: "com.google.Chrome",
        bundleName: "Chrome",
        inputSourceID: "com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin"
    )
    let items = StatusItemController.bindMenuItems(
        sources: sources(),
        rule: rule,
        bundleID: "com.google.Chrome",
        bundleName: "Chrome"
    )

    #expect(items.count == 2)
    #expect(items[0].state == .off, "the source that is not bound must not be marked")
    #expect(items[1].state == .on, "the bound source must be marked")
}

/// Without a rule there is nothing to mark.
@Test func withoutARuleNothingIsMarkedInTheBindMenu() {
    let items = StatusItemController.bindMenuItems(
        sources: sources(),
        rule: nil,
        bundleID: "com.google.Chrome",
        bundleName: "Chrome"
    )

    #expect(items.allSatisfy { $0.state == .off })
}

/// A rule that points at a source which is no longer installed must not mark
/// an unrelated source.
@Test func aRuleForAMissingSourceMarksNothing() {
    let rule = AppRule(
        bundleID: "com.google.Chrome",
        bundleName: "Chrome",
        inputSourceID: "com.gone.inputmethod"
    )
    let items = StatusItemController.bindMenuItems(
        sources: sources(),
        rule: rule,
        bundleID: "com.google.Chrome",
        bundleName: "Chrome"
    )

    #expect(items.allSatisfy { $0.state == .off })
}

/// The item has to carry the app it binds, so the rule lands on the app the
/// menu named.
@Test func theBindItemsCarryTheAppTheyBind() {
    let items = StatusItemController.bindMenuItems(
        sources: sources(),
        rule: nil,
        bundleID: "com.google.Chrome",
        bundleName: "Chrome"
    )

    #expect(items.count == 2)
    #expect(items[0].title == "ABC")
    #expect(items[1].title == "拼音")
}
