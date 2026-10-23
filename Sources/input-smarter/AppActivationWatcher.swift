import AppKit
import Foundation

/// Watches which application is frontmost and applies the matching rule.
///
/// This is the core of the product: Input Source Pro does the same thing with
/// `NSWorkspace`'s activation notification, then drives the switch through the
/// Text Input Sources API.
final class AppActivationWatcher {
    /// Bundle identifier of the watcher itself — never react to our own app.
    static let ownBundleID = Bundle.main.bundleIdentifier ?? "com.input-smarter"

    /// Injected so the switching logic can be exercised without touching the
    /// real system input source.
    var select: (InputSourceID) -> Bool = { InputSourceRegistry.select($0) }
    var readCurrent: () -> InputSourceID? = { InputSourceRegistry.current() }

    private let store: RuleStore
    private var token: NSObjectProtocol?
    /// Input source that was active before we switched into a rule-bound app.
    /// Restored when that app is left and the rule asks for it.
    private var suspendedSource: InputSourceID?
    /// Bundle id of the app we switched into, if any.
    private var suspendedForBundleID: String?

    init(store: RuleStore = .shared) {
        self.store = store
    }

    func start() {
        guard token == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        token = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleActivation(of: app)
        }
        // The app that is already frontmost never sends an activation
        // notification, so its rule is applied here.
        reapply()
    }

    func stop() {
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        token = nil
    }

    /// Apply the rule for a newly frontmost application.
    func handleActivation(of app: NSRunningApplication) {
        let bundleID = app.bundleIdentifier ?? ""
        let config = store.configuration
        Log.debug("[activate] \(bundleID) rules=\(config.appRules.map(\.bundleID))")

        // Did we just come out of a rule-bound app?
        var leftRuleApp = false

        // Leaving a rule-bound app: restore what was active before we entered.
        if let previous = suspendedForBundleID, previous != bundleID {
            leftRuleApp = true
            restore(config.rule(for: previous))
            suspendedSource = nil
            suspendedForBundleID = nil
        }

        // The rule for the app we are in may have been removed while we were
        // inside it: the user's input source has to come back.
        if suspendedForBundleID == bundleID, config.rule(for: bundleID) == nil {
            leftRuleApp = true
            restore(nil)
            suspendedSource = nil
            suspendedForBundleID = nil
        }

        guard bundleID != Self.ownBundleID else { return }

        guard let rule = config.rule(for: bundleID) else {
            Log.debug("[activate] no rule for \(bundleID)")
            // The default source applies to apps without a rule — but not
            // right after leaving one, where the rule (or its restore) decides.
            if !leftRuleApp, let fallback = config.defaultInputSourceID {
                let target = InputSourceID(composite: fallback)
                if target != readCurrent() {
                    let ok = select(target)
                    Log.debug("[activate] default source \(target.composite) select=\(ok)")
                }
            }
            return
        }
        let target = InputSourceID(composite: rule.inputSourceID)
        guard target != readCurrent() else { return }

        // Remember where we came from so a restore rule can come back.
        if suspendedForBundleID == nil, let current = readCurrent() {
            suspendedSource = current
            suspendedForBundleID = bundleID
        }
        let ok = select(target)
        Log.debug("[activate] rule matched \(bundleID) -> \(target.composite) select=\(ok)")
    }

    /// Re-evaluate the rules against the app that is frontmost right now.
    ///
    /// Used when the configuration changes: a rule that was just added for the
    /// frontmost app has to take effect without waiting for the next app
    /// switch, and a rule that was just removed has to give the user's input
    /// source back.
    func reapply() {
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        handleActivation(of: front)
    }

    /// Put the source back that was active before we switched into the app.
    ///
    /// A missing rule means the rule was removed while we were inside the app:
    /// the user's source is restored in that case too.
    private func restore(_ rule: AppRule?) {
        guard rule?.restoreKeyboard != false else { return }
        guard let saved = suspendedSource else { return }
        _ = select(saved)
    }
}
