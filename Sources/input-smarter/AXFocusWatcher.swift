import AppKit
import ApplicationServices
import Foundation

/// AX role strings.
///
/// The SDK exposes only a handful of role constants (`kAXTextFieldRole`,
/// `kAXTextAreaRole`, …); the roles that matter here — the browser page
/// (`AXWebArea`) and the omnibox variants — have to be spelled out.
private enum AXRole {
    static let webArea = "AXWebArea"
    static let textField = "AXTextField"
    static let comboBox = "AXComboBox"
    static let searchField = "AXSearchField"
    static let textArea = "AXTextArea"
}

/// Detects when a browser's address bar has focus and applies a browser rule.
///
/// Input Source Pro decides "is the user typing in the address bar?" with the
/// Accessibility API rather than WebKit or AppleScript — its binary imports
/// `AXObserver*` and `AXUIElement*` but no `WK*` or `NSAppleScript` symbols.
///
/// The test used here is localisation independent: walk up from the focused
/// element. The browser page is an `AXWebArea`, so reaching it means the
/// focus is inside the content; a text field that is *not* under an
/// `AXWebArea` is the browser chrome, which for a browser is the address bar.
final class AXFocusWatcher {
    /// Called with the browser bundle id and whether the address bar is focused.
    var onFocusChange: ((String, Bool) -> Void)?

    private let store: RuleStore
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var observedBundleID: String?
    private var runLoopSource: CFRunLoopSource?
    private var token: NSObjectProtocol?

    init(store: RuleStore = .shared) {
        self.store = store
    }

    func start() {
        guard token == nil else { return }
        // `NSWorkspace` publishes on its own notification centre, not on
        // `NotificationCenter.default` — subscribing to the wrong one means
        // the observer is never told about anything.
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.observe(pid: app.processIdentifier)
        }
        // The app that is already frontmost never sends an activation
        // notification, so start with it.
        if let front = NSWorkspace.shared.frontmostApplication {
            observe(pid: front.processIdentifier)
        }
    }

    func stop() {
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        token = nil
        teardown()
    }

    /// Start watching the focused element of a given application.
    func observe(pid: pid_t) {
        guard pid != observedPID else { return }
        let previousBundleID = observedBundleID
        teardown()
        observedPID = pid
        observedBundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier

        var axObserver: AXObserver?
        // The callback is a C function pointer, so it cannot capture `self`;
        // the instance travels through the notification's refcon instead.
        let status = AXObserverCreate(pid, { _, _, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<AXFocusWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.handle(notification: notification)
        }, &axObserver)
        guard status == .success, let axObserver else {
            Log.error("[ax] cannot observe pid \(pid): \(status.rawValue)")
            return
        }
        self.observer = axObserver

        // Notifications have to be registered against the application's
        // element, not the observer.
        let application = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(axObserver, application, notification as CFString, refcon)
        }

        let source = AXObserverGetRunLoopSource(axObserver)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source

        // The app we were watching is gone: let a browser rule restore the
        // input source it had suspended.
        if let previousBundleID {
            onFocusChange?(previousBundleID, false)
        }
    }

    private func teardown() {
        if let observer, let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            let application = AXUIElementCreateApplication(observedPID)
            AXObserverRemoveNotification(observer, application, kAXFocusedUIElementChangedNotification as CFString)
            AXObserverRemoveNotification(observer, application, kAXFocusedWindowChangedNotification as CFString)
        }
        observer = nil
        runLoopSource = nil
        observedPID = 0
        observedBundleID = nil
    }

    private func handle(notification: CFString) {
        // The bundle id of the *observed* app, not of whatever happens to be
        // frontmost: the observer belongs to the app it was created for.
        guard let bundleID = observedBundleID else { return }
        onFocusChange?(bundleID, addressBarHasFocus())
    }

    /// Inspect the currently focused element of the frontmost application.
    func addressBarHasFocus() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard status == .success, let element = focused else { return false }
        return isAddressBar(element as! AXUIElement)
    }

    /// Walk up from the focused element.
    ///
    /// The page is an `AXWebArea`, so reaching one means the focus is in the
    /// content rather than in the address bar. A text field that is not under
    /// an `AXWebArea` is the browser chrome — the address bar.
    func isAddressBar(_ element: AXUIElement) -> Bool {
        var current: AXUIElement = element
        var sawTextField = false
        for _ in 0..<12 {
            guard let role = stringAttribute(kAXRoleAttribute, of: current) else { return sawTextField }
            if role == AXRole.webArea { return false }
            if role == AXRole.textField || role == AXRole.comboBox || role == AXRole.searchField {
                sawTextField = true
            }
            guard let parent = elementAttribute(kAXParentAttribute, of: current) else { break }
            current = parent
        }
        return sawTextField
    }

    // MARK: - AX attribute helpers

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }

    private func elementAttribute(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
