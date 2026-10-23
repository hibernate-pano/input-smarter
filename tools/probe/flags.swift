import AppKit
import Foundation

// Does NSEvent's global flagsChanged monitor work WITHOUT Input Monitoring?
// (Input Source Pro ships this feature while holding only an Accessibility
// grant, and its source says "flagsChanged works without Input Monitoring".)

let path = "/tmp/flags-changed.log"
try? "".write(toFile: path, atomically: true, encoding: .utf8)
func log(_ s: String) {
    let fh = FileHandle(forWritingAtPath: path)
    fh?.seekToEndOfFile()
    if let d = (s + "\n").data(using: .utf8) { fh?.write(d) }
    try? fh?.close()
}

log("pid=\(ProcessInfo.processInfo.processIdentifier) AXTrusted=\(AXIsProcessTrusted())")

var count = 0
let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { event in
    count += 1
    log("flagsChanged keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue) type=\(event.type.rawValue)")
}
log("global monitor installed: \(monitor != nil)")

DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    log("FINAL count=\(count)")
    exit(0)
}
CFRunLoopRun()
