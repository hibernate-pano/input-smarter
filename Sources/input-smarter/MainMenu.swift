import AppKit

/// The actions of the menu of the app.
///
/// The app lives in the menu bar, so it has no menu of its own. It needs one
/// while the settings window is open: the app takes the focus then, and an
/// active app without a menu would leave the menu bar of the screen empty.
@MainActor
final class MenuActions: NSObject {
    var onOpenSettings: (() -> Void)?

    @objc func openSettings(_ sender: Any?) {
        onOpenSettings?()
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

/// The menu bar of the app while it is the active application.
enum MainMenu {
    /// Install the menu. It only shows up while the app is in front.
    static func install(actions: MenuActions) {
        let appMenu = NSMenu()
        appMenu.title = "input-smarter"

        let settings = NSMenuItem(
            title: "设置…",
            action: #selector(MenuActions.openSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = actions
        appMenu.addItem(settings)

        appMenu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 input-smarter",
            action: #selector(MenuActions.quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = actions
        appMenu.addItem(quit)

        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        mainMenu.setSubmenu(appMenu, for: appMenuItem)
        NSApp.mainMenu = mainMenu
    }
}
