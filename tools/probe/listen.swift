import ApplicationServices
import CoreGraphics
import Foundation

// Decides the architecture: with ONLY Accessibility (no Input Monitoring),
// does a listen-only CGEventTap actually deliver real key events?
let out = URL(fileURLWithPath: "/tmp/tap-listen.log")
try? "".write(to: out, atomically: true, encoding: .utf8)
func append(_ s: String) {
    let fh = FileHandle(forWritingAtPath: "/tmp/tap-listen.log")
    if let fh { fh.seekToEndOfFile(); if let d = (s + "\n").data(using: .utf8) { fh.write(d) }; try? fh.close() }
}

append("pid=\(ProcessInfo.processInfo.processIdentifier) AXTrusted=\(AXIsProcessTrusted()) at \(Date().timeIntervalSince1970)")

let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
    | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)

var counts: [String: Int] = [:]
let lock = NSLock()
let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                            options: .listenOnly, eventsOfInterest: mask,
                            callback: { proxy, type, event, _ in
        lock.lock()
        defer { lock.unlock() }
        switch type {
        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            counts["keyDown"] = (counts["keyDown"] ?? 0) + 1
            append("keyDown keyCode=\(key) flags=\(event.flags.rawValue)")
        case .flagsChanged:
            counts["flagsChanged"] = (counts["flagsChanged"] ?? 0) + 1
            append("flagsChanged flags=\(event.flags.rawValue)")
        case .tapDisabledByTimeout:
            append("tapDisabledByTimeout")
        default: break
        }
        return Unmanaged.passUnretained(event)
    }, userInfo: nil)

append("tapCreate -> \(tap == nil ? "nil" : "ok")")
guard let tap else { exit(1) }
let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
append("tap enabled, listening 90s")

DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
    append("FINAL counts=\(counts)")
    exit(0)
}
CFRunLoopRun()
