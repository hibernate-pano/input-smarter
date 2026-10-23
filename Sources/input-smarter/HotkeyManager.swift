import Carbon
import Foundation

/// Registers system-wide hotkeys that cycle between input sources.
///
/// Uses Carbon's `RegisterEventHotKey` rather than a `CGEventTap`: Carbon
/// hotkeys are delivered to any application without the Input Monitoring
/// permission, which is why Input Source Pro only holds an Accessibility
/// grant.
final class HotkeyManager {
    /// One registered hotkey.
    private final class Registration {
        let binding: HotkeyBinding
        let ref: EventHotKeyRef
        init(binding: HotkeyBinding, ref: EventHotKeyRef) {
            self.binding = binding
            self.ref = ref
        }
    }

    /// Called with the binding whose hotkey fired.
    var onTrigger: ((HotkeyBinding) -> Void)?
    /// Called when the hotkey should cycle to the next source in the group.
    var onCycle: ((HotkeyBinding) -> Void)?

    private var registrations: [UUID: Registration] = [:]
    private var handlerRef: EventHandlerRef?
    private var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

    /// Carbon wants a stable four-char signature per application.
    private static let signature: OSType = {
        let chars = Array("ISPR".utf8)
        return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16) | (OSType(chars[2]) << 8) | OSType(chars[3])
    }()

    func start() {
        guard handlerRef == nil else { return }
        var spec = eventType
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                Log.debug("[hotkey] event id=\(hotKeyID.id) sig=\(hotKeyID.signature)")
                HotkeyManager.shared?.fire(hotKeyID)
                return noErr
            },
            1,
            &spec,
            nil,
            &handlerRef
        )
    }

    func stop() {
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    /// Register (or re-register) a hotkey.
    func register(_ binding: HotkeyBinding) {
        unregister(id: binding.id)
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(truncatingIfNeeded: binding.id.hashValue))
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        Log.debug("[hotkey] register key=\(binding.keyCode) mod=\(binding.modifiers) status=\(status)")
        guard status == noErr, let hotKeyRef else {
            // -9878 (`eventHotKeyExistsErr`) means another hotkey already owns
            // this key and modifier combination.
            Log.error("[hotkey] cannot register key=\(binding.keyCode) mod=\(binding.modifiers): status \(status)")
            return
        }
        registrations[binding.id] = Registration(binding: binding, ref: hotKeyRef)
    }

    func unregister(id: UUID) {
        guard let registration = registrations.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(registration.ref)
    }

    /// Re-register everything from the store (used when the config changes).
    ///
    /// A binding that keeps its id but changes its key code or modifiers has
    /// to be registered again: Carbon keeps the old registration otherwise,
    /// and the hotkey would keep firing the old combination.
    func sync(_ bindings: [HotkeyBinding]) {
        let wanted = Set(bindings.map(\.id))
        for id in registrations.keys.filter({ !wanted.contains($0) }) {
            unregister(id: id)
        }
        for binding in bindings {
            if let existing = registrations[binding.id] {
                if existing.binding.keyCode == binding.keyCode,
                   existing.binding.modifiers == binding.modifiers {
                    continue
                }
                unregister(id: binding.id)
            }
            register(binding)
        }
    }

    /// The bindings that collide with `binding` on key code and modifiers.
    ///
    /// Carbon only allows one hotkey per combination: a second registration
    /// fails with `eventHotKeyExistsErr` and is dropped silently.
    static func conflicts(with binding: HotkeyBinding, in bindings: [HotkeyBinding]) -> [HotkeyBinding] {
        bindings.filter {
            $0.id != binding.id && $0.keyCode == binding.keyCode && $0.modifiers == binding.modifiers
        }
    }

    private func fire(_ hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == Self.signature else { return }
        // Carbon only carries a UInt32 id, so the binding is looked up by the
        // same truncated hash that was used to register it.
        Log.debug("[hotkey] sig ok=\(hotKeyID.signature == Self.signature) id=\(hotKeyID.id) known=\(registrations.values.map { UInt32(truncatingIfNeeded: $0.binding.id.hashValue) })")
        guard let registration = registrations.values.first(where: {
            UInt32(truncatingIfNeeded: $0.binding.id.hashValue) == hotKeyID.id
        }) else {
            Log.debug("[hotkey] NO REGISTRATION MATCH")
            return
        }
        onCycle?(registration.binding)
    }

    /// Shared instance used by the Carbon event handler callback.
    static var shared: HotkeyManager?
}
