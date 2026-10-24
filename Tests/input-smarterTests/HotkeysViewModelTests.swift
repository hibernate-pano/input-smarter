import Carbon
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

private func combo(_ keyCode: UInt16 = 49, _ modifiers: UInt32 = UInt32(optionKey)) -> KeyCombo {
    KeyCombo(keyCode: keyCode, modifiers: modifiers)
}

/// A hotkey the user recorded has to end up in the configuration.
@Test @MainActor func aRecordedHotkeyIsStored() {
    let store = makeStore()
    let model = HotkeysViewModel(store: store, sources: [source("拼音"), source("ABC")])

    model.beginAdding()
    model.setDraftCombo(combo())
    model.addDraftSource(source("拼音").id.composite)
    model.commit()

    let hotkeys = store.configuration.hotkeys
    #expect(hotkeys.count == 1)
    #expect(hotkeys.first?.keyCode == 49)
    #expect(hotkeys.first?.modifiers == UInt32(optionKey))
    #expect(hotkeys.first?.inputSourceIDs == [source("拼音").id.composite])
    #expect(model.hotkeys.count == 1, "the list has to show the hotkey that was just added")
}

/// Nothing was pressed: there is no hotkey to store.
@Test @MainActor func aHotkeyWithoutAKeyIsNotStored() {
    let store = makeStore()
    let model = HotkeysViewModel(store: store, sources: [source("拼音")])

    model.beginAdding()
    model.addDraftSource(source("拼音").id.composite)
    model.commit()

    #expect(store.configuration.hotkeys.isEmpty)
    #expect(model.errorMessage != nil)
}

/// A hotkey without an input source would do nothing.
@Test @MainActor func aHotkeyWithoutAnInputSourceIsNotStored() {
    let store = makeStore()
    let model = HotkeysViewModel(store: store, sources: [source("拼音")])

    model.beginAdding()
    model.setDraftCombo(combo())
    model.commit()

    #expect(store.configuration.hotkeys.isEmpty)
    #expect(model.errorMessage != nil)
}

/// A bare key would swallow that key everywhere, so it is refused.
@Test @MainActor func aHotkeyWithoutAModifierIsRefused() {
    let store = makeStore()
    let model = HotkeysViewModel(store: store, sources: [source("拼音")])

    model.beginAdding()
    model.setDraftCombo(combo(49, 0))
    model.addDraftSource(source("拼音").id.composite)
    model.commit()

    #expect(store.configuration.hotkeys.isEmpty)
    #expect(model.errorMessage != nil)
}

/// Carbon keeps only one hotkey per combination, so the second one has to be
/// refused instead of being dropped by the system.
@Test @MainActor func aCombinationThatIsAlreadyUsedIsRefused() {
    let store = makeStore()
    store.setHotkey(HotkeyBinding(
        keyCode: 49,
        modifiers: UInt32(optionKey),
        inputSourceIDs: [source("拼音").id.composite]
    ))
    let model = HotkeysViewModel(store: store, sources: [source("拼音")])

    model.beginAdding()
    model.setDraftCombo(combo())
    model.addDraftSource(source("ABC").id.composite)
    model.commit()

    #expect(store.configuration.hotkeys.count == 1, "the second hotkey with the same combination must not be stored")
    #expect(model.errorMessage != nil)
}

/// The order the input sources were picked in is the order they cycle in.
@Test @MainActor func theInputSourcesCycleInTheOrderTheyWerePicked() {
    let store = makeStore()
    let model = HotkeysViewModel(store: store, sources: [source("拼音"), source("ABC")])

    model.beginAdding()
    model.setDraftCombo(combo())
    model.addDraftSource(source("ABC").id.composite)
    model.addDraftSource(source("拼音").id.composite)
    model.commit()

    #expect(store.configuration.hotkeys.first?.inputSourceIDs
        == [source("ABC").id.composite, source("拼音").id.composite])
}

/// A source that is already in the cycle is not added twice.
@Test @MainActor func anInputSourceIsNotAddedTwice() {
    let store = makeStore()
    let model = HotkeysViewModel(store: store, sources: [source("拼音")])

    model.beginAdding()
    model.addDraftSource(source("拼音").id.composite)
    model.addDraftSource(source("拼音").id.composite)

    #expect(model.draftSources == [source("拼音").id.composite])
}

/// A hotkey is removed from the list when it is deleted.
@Test @MainActor func aHotkeyIsRemoved() {
    let store = makeStore()
    let model = HotkeysViewModel(store: store, sources: [source("拼音")])
    store.setHotkey(HotkeyBinding(
        keyCode: 49,
        modifiers: UInt32(optionKey),
        inputSourceIDs: [source("拼音").id.composite]
    ))
    model.reload()
    #expect(model.hotkeys.count == 1)

    guard let hotkey = model.hotkeys.first else { return }
    model.remove(hotkey)

    #expect(store.configuration.hotkeys.isEmpty)
    #expect(model.hotkeys.isEmpty)
}

/// Cancelling the editor leaves nothing behind.
@Test @MainActor func cancellingTheEditorForgetsTheDraft() {
    let store = makeStore()
    let model = HotkeysViewModel(store: store, sources: [source("拼音")])

    model.beginAdding()
    model.setDraftCombo(combo())
    model.addDraftSource(source("拼音").id.composite)
    model.cancelAdding()

    #expect(model.isAdding == false)
    #expect(model.draftCombo == nil)
    #expect(model.draftSources.isEmpty)
}
