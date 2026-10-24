import AppKit
import SwiftUI

/// A field that records the key combination the user presses.
///
/// The combination is captured from the raw key events: the key code and the
/// modifiers are exactly what the system would register, which typing the
/// combination as text could not do for the keys that have no character.
struct KeyRecorderField: NSViewRepresentable {
    /// Called with the combination that was pressed; nil when nothing was.
    var onChange: (KeyCombo?) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onChange = onChange
    }
}

/// The view that captures the key presses.
final class KeyCaptureView: NSView {
    var onChange: ((KeyCombo?) -> Void)?

    /// The key that was pressed; nil while no key was pressed.
    private var keyCode: UInt16?
    /// The modifiers that are held down.
    private var modifiers: UInt32 = 0

    override var acceptsFirstResponder: Bool { true }

    /// The field is clicked, not typed into: it takes the click itself.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // The view can only receive the keys once it is in a window.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // The app lives in the menu bar: it has to be the active app before
        // it can receive the key presses.
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        keyCode = event.keyCode
        modifiers = KeyCombo.carbonModifiers(from: event.modifierFlags)
        publish()
    }

    override func flagsChanged(with event: NSEvent) {
        let mask = KeyCombo.carbonModifiers(from: event.modifierFlags)
        // A modifier that is let go does not take the combination away: it is
        // usually released before the key itself.
        if mask != 0 { modifiers = mask }
        publish()
    }

    private func publish() {
        onChange?(keyCode.map { KeyCombo(keyCode: $0, modifiers: modifiers) })
    }
}
