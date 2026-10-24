import AppKit
import SwiftUI

/// A window that can take the keyboard while the app lives in the menu bar.
///
/// An accessory app is not the active application, so a normal window cannot
/// become key: the search box would not accept any text. A non-activating
/// panel can.
final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The settings window.
///
/// It holds the app list: the place where a rule is created for an app that
/// is not the one in front right now.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Called after a rule was changed, so the running app can apply it right
    /// away.
    var onRulesChanged: (() -> Void)?

    private var window: NSWindow?
    private var model: AppRulesViewModel?
    private let store = RuleStore.shared

    /// Open the window, bringing it to the front if it is already open.
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        refresh()
        takeFocus()
        window.makeKeyAndOrderFront(nil)
        Log.debug("[settings] isActive=\(NSApp.isActive) key=\(window.isKeyWindow)")
    }

    /// Re-read the rules, e.g. after the command line changed them.
    func reload() {
        model?.reload()
    }

    /// Make the app the active application.
    ///
    /// An app in the menu bar is not the active application, and it cannot
    /// become one: the activation policy has to be "regular" for that. The
    /// window needs the keyboard — the search box is no use without it — and
    /// only the active application gets one.
    ///
    /// The policy is put back to "accessory" when the window is closed, so
    /// the app is a menu bar app again. The focus goes back to the app the
    /// user came from by itself: macOS remembers which app was in front.
    private func takeFocus() {
        guard !NSApp.isActive else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The window is closed: the app goes back to being a menu bar app.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let model = AppRulesViewModel(store: store, installed: [], sources: [])
        model.onRulesChanged = { [weak self] in self?.onRulesChanged?() }
        self.model = model

        // A panel that does not activate the app: an app in the menu bar is
        // not the active application, so a normal window cannot become key
        // and the search box could not be typed into.
        let window = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "input-smarter 设置"
        // The window is kept alive by this controller, so it may be closed
        // without being deallocated.
        window.isReleasedWhenClosed = false
        window.delegate = self
        // The panel becomes key only when it needs the keyboard. That way the
        // search box can be typed into, without the app in the menu bar
        // taking the focus away from the app the user is working in.
        window.becomesKeyOnlyIfNeeded = true
        window.contentView = NSHostingView(rootView: AppRulesView(model: model))
        window.setFrameAutosaveName("input-smarter.settings")
        window.center()
        return window
    }

    /// Read the apps and the input sources again.
    ///
    /// The apps are read in the background: reading the info of a few hundred
    /// bundles takes long enough to be noticed.
    private func refresh() {
        guard let model else { return }
        model.setSources(InputSourceRegistry.availableSources())
        // The source that is in use right now is the one a newly added app
        // is bound to.
        model.currentSourceID = InputSourceRegistry.current()?.composite
        model.beginLoading()
        // The apps that are configured but live outside the usual folders are
        // found through Launch Services.
        let configured = store.configuration.appRules.map(\.bundleID)
        let resolved = configured.compactMap { AppCatalog.app(withBundleID: $0) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanned = AppCatalog.installedApps(in: AppCatalog.defaultDirectories)
            let apps = AppCatalog.merge(scanned, resolved)
            DispatchQueue.main.async {
                self?.model?.setInstalled(apps)
            }
        }
    }
}
