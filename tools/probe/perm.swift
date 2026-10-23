import AppKit
import ApplicationServices
import CoreGraphics
import Carbon

func log(_ s: String) { fputs(s + "\n", stderr) }
let pid = ProcessInfo.processInfo.processIdentifier
log("probe pid: \(pid)")

log("AXIsProcessTrusted: \(AXIsProcessTrusted())")

log("> creating CGEventTap")
let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                            options: .listenOnly, eventsOfInterest: mask,
                            callback: { _, _, _, _ in nil }, userInfo: nil)
log("CGEventTapCreate: \(tap == nil ? "nil" : "ok")")

log("> creating AXObserver")
var axObs: AXObserver? = nil
let axErr = AXObserverCreate(pid, { _, _, _, _ in }, &axObs)
log("AXObserverCreate: \(axErr == .success ? "ok" : "err \(axErr.rawValue)")")

log("> NSWorkspace")
let ws = NSWorkspace.shared
log("frontmost: \(ws.frontmostApplication?.bundleIdentifier ?? "<nil>")")

log("> TIS notifications")
for sym in ["kTISNotifySelectedKeyboardInputSourceChanged", "kTISNotifyEnabledKeyboardInputSourcesChanged"] {
    let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), sym)
    log("\(sym): \(p == nil ? "MISSING" : "present")")
}

log("> TIS lookup by id")
let list = TISCreateInputSourceList(nil, true).takeRetainedValue() as? [TISInputSource] ?? []
for want in ["com.tencent.inputmethod.wetype.pinyin", "com.apple.keylayout.ABC", "com.tencent.inputmethod.wetype"] {
    let n = list.filter { src in
        guard let p = TISGetInputSourceProperty(src, "TISPropertyInputSourceID" as CFString) else { return false }
        return (p as! CFString) as String == want
    }.count
    log("  \(want): \(n) match(es)")
}
log("DONE")
