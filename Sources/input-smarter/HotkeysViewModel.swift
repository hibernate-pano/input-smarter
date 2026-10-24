import Combine
import Foundation

/// Drives the hotkey page of the settings window.
///
/// A hotkey is a key combination and the group of input sources it cycles
/// through. The page lists the hotkeys that exist and lets the user record a
/// new one.
@MainActor
final class HotkeysViewModel: ObservableObject {
    /// The hotkeys that are configured.
    @Published private(set) var hotkeys: [HotkeyBinding] = []
    /// True while a new hotkey is being recorded.
    @Published private(set) var isAdding: Bool = false
    /// The combination that was recorded so far.
    @Published private(set) var draftCombo: KeyCombo?
    /// The input sources the new hotkey cycles through, in order.
    @Published private(set) var draftSources: [String] = []
    /// Why the last attempt to store the new hotkey failed.
    @Published private(set) var errorMessage: String?

    /// The input sources the user can pick from.
    private(set) var sources: [InputSourceInfo]

    /// Called when the recording starts or stops.
    ///
    /// The app's own hotkeys are taken out of the way while a combination is
    /// being recorded: a combination that is already registered is swallowed
    /// by the system and would never reach the recorder.
    var onRecordingChanged: ((Bool) -> Void)?

    private let store: RuleStore

    init(store: RuleStore, sources: [InputSourceInfo]) {
        self.store = store
        self.sources = sources
        reload()
    }

    /// Hand over the input sources the user can pick from.
    func setSources(_ sources: [InputSourceInfo]) {
        self.sources = sources
    }

    /// Read the hotkeys again, e.g. after the command line changed them.
    func reload() {
        hotkeys = store.configuration.hotkeys
    }

    /// Start recording a new hotkey.
    func beginAdding() {
        isAdding = true
        draftCombo = nil
        draftSources = []
        errorMessage = nil
        onRecordingChanged?(true)
    }

    /// Give up on the hotkey that was being recorded.
    func cancelAdding() {
        isAdding = false
        draftCombo = nil
        draftSources = []
        errorMessage = nil
        onRecordingChanged?(false)
    }

    /// The combination the user pressed.
    func setDraftCombo(_ combo: KeyCombo?) {
        draftCombo = combo
        errorMessage = nil
    }

    /// Add an input source to the cycle of the new hotkey.
    func addDraftSource(_ composite: String) {
        guard !draftSources.contains(composite) else { return }
        draftSources.append(composite)
        errorMessage = nil
    }

    /// Take an input source out of the cycle of the new hotkey.
    func removeDraftSource(_ composite: String) {
        draftSources.removeAll { $0 == composite }
    }

    /// The input sources that are not in the cycle yet.
    var availableSources: [InputSourceInfo] {
        sources.filter { !draftSources.contains($0.id.composite) }
    }

    /// The name of an input source, for the list and the editor.
    func name(of composite: String) -> String {
        sources.first { $0.id.composite == composite }?.displayName
            ?? InputSourceID(composite: composite).sourceID
    }

    /// Whether the new hotkey has everything it needs.
    var canCommit: Bool {
        draftCombo != nil && !draftSources.isEmpty
    }

    /// Store the hotkey that was recorded.
    ///
    /// A hotkey without a key, without an input source or without a modifier
    /// would either do nothing or swallow a key everywhere, so it is refused.
    /// A combination that is already used is refused as well: Carbon keeps
    /// only one hotkey per combination and drops the second one silently.
    func commit() {
        guard let combo = draftCombo else {
            errorMessage = "还没有按下组合键"
            return
        }
        guard combo.modifiers != 0 else {
            errorMessage = "至少要带一个修饰键（⌘ ⌥ ⇧ ⌃）"
            return
        }
        guard !draftSources.isEmpty else {
            errorMessage = "至少要选一个输入法"
            return
        }
        let binding = HotkeyBinding(
            keyCode: combo.keyCode,
            modifiers: combo.modifiers,
            inputSourceIDs: draftSources
        )
        guard HotkeyManager.conflicts(with: binding, in: store.configuration.hotkeys).isEmpty else {
            errorMessage = "这个组合键已经被别的快捷键用了"
            return
        }
        store.setHotkey(binding)
        reload()
        cancelAdding()
    }

    /// Delete a hotkey.
    func remove(_ hotkey: HotkeyBinding) {
        store.removeHotkey(id: hotkey.id)
        reload()
    }
}
