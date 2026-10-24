import Foundation

/// Minimal logging.
///
/// Debug output goes to stderr and only when `IS_DEBUG` is set, so the menu
/// bar app stays quiet during normal use. Errors always go to stderr *and* to
/// a log file: the app usually runs as a LaunchAgent, where stderr ends up
/// nowhere and an error would otherwise be invisible.
enum Log {
    private static let debugEnabled = ProcessInfo.processInfo.environment["IS_DEBUG"] != nil

    /// `~/Library/Logs/input-smarter.log`
    ///
    /// `INPUT_SMARTER_LOG` overrides the path — the test suite writes there
    /// instead of into the user's log.
    private static let logURL: URL = {
        if let override = ProcessInfo.processInfo.environment["INPUT_SMARTER_LOG"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("input-smarter.log")
    }()

    static func debug(_ message: @autoclosure () -> String) {
        guard debugEnabled else { return }
        let text = message()
        write(text)
        // The debug output goes to the log file as well: the app usually runs
        // as a LaunchAgent, where stderr ends up nowhere.
        appendToFile(text)
    }

    static func error(_ message: @autoclosure () -> String) {
        let text = "ERROR: " + message()
        write(text)
        appendToFile(text)
    }

    private static func write(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static func appendToFile(_ message: String) {
        let line = message + "\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Nowhere left to report this.
        }
    }
}
