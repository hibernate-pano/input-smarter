import CoreGraphics
import Testing

@testable import input_smarter

/// Guards the hardcoded TIS property keys.
///
/// `kTISProperty*` are exported by HIToolbox but no longer declared in the
/// SDK headers, so the registry uses string literals. Their real values do not
/// match the symbol names (`kTISPropertyInputSourceIsEnabled` is really
/// `"TSMInputSourcePropertyIsEnabled"`), so a silent typo would make every
/// lookup return nil. This test reads the real values back out of the running
/// system and compares.
@Test func literalKeysMatchExportedSymbols() throws {
    func exportedValue(_ symbol: String) -> String? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) else { return nil }
        return pointer.assumingMemoryBound(to: CFString.self).pointee as String
    }

    let expected: [(String, CFString)] = [
        ("kTISPropertyInputSourceID", TISKey.inputSourceID),
        ("kTISPropertyInputSourceCategory", TISKey.category),
        ("kTISPropertyInputSourceType", TISKey.type),
        ("kTISPropertyInputSourceIsEnabled", TISKey.isEnabled),
        ("kTISPropertyInputSourceIsSelectCapable", TISKey.isSelectCapable),
        ("kTISPropertyInputSourceIsASCIICapable", TISKey.isASCIICapable),
        ("kTISPropertyInputModeID", TISKey.inputModeID),
        ("kTISPropertyBundleID", TISKey.bundleID),
        ("kTISPropertyLocalizedName", TISKey.localizedName),
    ]
    for (symbol, literal) in expected {
        let exported = try #require(exportedValue(symbol), "\(symbol) is not exported by HIToolbox")
        #expect(exported == literal as String, "\(symbol) literal drifted")
    }
}

@Test func plainLayoutHasNoMode() {
    let id = InputSourceID(composite: "com.apple.keylayout.ABC")
    #expect(id.sourceID == "com.apple.keylayout.ABC")
    #expect(id.modeID == nil)
    #expect(id.composite == "com.apple.keylayout.ABC")
}

@Test func modeEnabledIMEKeepsBothHalves() {
    let composite = "com.tencent.inputmethod.wetype.pinyin::com.tencent.inputmethod.wetype.pinyin"
    let id = InputSourceID(composite: composite)
    #expect(id.sourceID == "com.tencent.inputmethod.wetype.pinyin")
    #expect(id.modeID == "com.tencent.inputmethod.wetype.pinyin")
    #expect(id.composite == composite)
}

@Test func emptyModeIsTreatedAsAbsent() {
    let id = InputSourceID(composite: "com.apple.keylayout.ABC::")
    #expect(id.modeID == nil)
    #expect(id.composite == "com.apple.keylayout.ABC")
}

@Test func registrySeesEnabledSelectableSources() {
    let sources = InputSourceRegistry.availableSources()
    #expect(!sources.isEmpty, "no enabled input sources found")
    #expect(sources.allSatisfy { !$0.id.sourceID.isEmpty })
}

@Test func currentSourceRoundTrips() throws {
    let current = try #require(InputSourceRegistry.current(), "could not read the current input source")
    #expect(!current.sourceID.isEmpty)
    let reparsed = InputSourceID(composite: current.composite)
    #expect(reparsed == current)
}
