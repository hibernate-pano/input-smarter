import Carbon
import Foundation

// Read-only probe: enumerate keyboard input sources via the TIS layer.
// Confirms the CFSTR property keys and shows what this Mac actually has.
func tisKey(_ sym: String) -> CFString {
    // RTLD_DEFAULT on Darwin is (void*)-2
    guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), sym) else {
        fatalError("missing symbol \(sym)")
    }
    // symbol is a CFStringRef global; read it as an unretained pointer
    return p.assumingMemoryBound(to: CFString.self).pointee
}

func prop(_ key: CFString, _ src: TISInputSource) -> CFTypeRef? {
    guard let p = TISGetInputSourceProperty(src, key) else { return nil }
    return Unmanaged<CFTypeRef>.fromOpaque(p).takeUnretainedValue()
}
func s(_ key: CFString, _ src: TISInputSource) -> String {
    guard let p = prop(key, src) else { return "<nil>" }
    return (p as! CFString) as String
}
func b(_ key: CFString, _ src: TISInputSource) -> Bool {
    guard let p = prop(key, src) else { return false }
    return CFBooleanGetValue(p as! CFBoolean)
}

let kID = tisKey("kTISPropertyInputSourceID")
let kCat = tisKey("kTISPropertyInputSourceCategory")
let kType = tisKey("kTISPropertyInputSourceType")
let kEnabled = tisKey("kTISPropertyInputSourceIsEnabled")
let kSelectable = tisKey("kTISPropertyInputSourceIsSelectCapable")
let kASCII = tisKey("kTISPropertyInputSourceIsASCIICapable")
let kMode = tisKey("kTISPropertyInputModeID")
let kBundle = tisKey("kTISPropertyBundleID")
let kLocalName = tisKey("kTISPropertyLocalizedName")

print("key values: id=\(kID) cat=\(kCat) type=\(kType) enabled=\(kEnabled) selectable=\(kSelectable) ascii=\(kASCII) mode=\(kMode)")

let filter = [kCat as String: "TISCategoryKeyboardInputSource"] as CFDictionary
let list = TISCreateInputSourceList(filter, true).takeRetainedValue() as? [TISInputSource] ?? []
print("\nkeyboard-capable input sources: \(list.count)\n")
for src in list {
    let id = s(kID, src)
    let mode = s(kMode, src)
    let full = mode.isEmpty || mode == id ? id : "\(id)::\(mode)"
    print("  \(full)")
    print("      cat=\(s(kCat, src)) type=\(s(kType, src)) name=\(s(kLocalName, src)) bundle=\(s(kBundle, src))")
    print("      enabled=\(b(kEnabled, src)) selectable=\(b(kSelectable, src)) ascii=\(b(kASCII, src))")
}

print("\n--- current ---")
let cur = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
print("current id   :", s(kID, cur))
print("current mode :", s(kMode, cur))
print("ascii layout :", s(kID, TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()))
