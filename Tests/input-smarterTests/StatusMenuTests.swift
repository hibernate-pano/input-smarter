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

/// The default input source has to be marked, otherwise the menu cannot be
/// read at a glance.
@Test func theDefaultInputSourceIsMarkedInTheMenu() {
    let items = StatusItemController.defaultSourceMenuItems(
        sources: sources(),
        defaultID: "com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin"
    )

    #expect(items.count == 3, "the first item is the option of not having a default")
    #expect(items[0].title == "跟随系统（不设默认）")
    #expect(items[0].state == .off)
    #expect(items[1].state == .off)
    #expect(items[2].state == .on)
}

/// Without a default the system decides, and the menu has to say so.
@Test func theFollowSystemItemIsMarkedWhenThereIsNoDefault() {
    let items = StatusItemController.defaultSourceMenuItems(sources: sources(), defaultID: nil)

    #expect(items[0].state == .on)
    #expect(items[1].state == .off)
    #expect(items[2].state == .off)
}

/// The item has to carry the source it sets, so the right one is picked.
@Test func theDefaultSourceItemsCarryTheSourceTheySet() {
    let items = StatusItemController.defaultSourceMenuItems(sources: sources(), defaultID: nil)

    #expect(items[0].representedObject as? String == "")
    #expect(items[1].representedObject as? String == "com.apple.keylayout.ABC")
    #expect(items[2].representedObject as? String
        == "com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin")
}

/// Launch at login is a switch, so the menu has to show whether it is on.
@Test func theLaunchAtLoginItemShowsWhetherItIsOn() {
    #expect(StatusItemController.launchAtLoginItem(isEnabled: true).state == .on)
    #expect(StatusItemController.launchAtLoginItem(isEnabled: false).state == .off)
    #expect(StatusItemController.launchAtLoginItem(isEnabled: true).title == "开机自启")
}

/// The current input source is shown by name: an identifier is noise.
@Test func theCurrentInputSourceIsShownByName() {
    let name = StatusItemController.currentSourceName(
        sources: sources(),
        current: InputSourceID(sourceID: "com.apple.keylayout.ABC")
    )
    #expect(name == "ABC")
}

/// A source that is not in the list still has to be readable.
@Test func anUnknownCurrentInputSourceIsShownWithoutItsBundle() {
    let name = StatusItemController.currentSourceName(
        sources: sources(),
        current: InputSourceID(sourceID: "com.example.gone")
    )
    #expect(name == "gone")
}
