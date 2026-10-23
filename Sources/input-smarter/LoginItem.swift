import Foundation

/// Registers the app to launch at login.
///
/// `SMAppService.mainApp` is the modern API but it reports `.notFound` for
/// bundles outside /Applications, so this uses a LaunchAgent plist instead:
/// it works from any location, needs no entitlement, and the user can see
/// and delete it in `~/Library/LaunchAgents`.
enum LoginItem {
    static let label = "com.panbo.input-smarter"

    private static var agentsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private static var plistURL: URL {
        agentsDirectory.appendingPathComponent("\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Turn launch-at-login on or off. Returns a message describing the result.
    static func set(_ enabled: Bool) -> String {
        if enabled {
            return enable()
        }
        return disable()
    }

    private static func enable() -> String {
        guard let executable = Bundle.main.executablePath else {
            return "cannot locate the executable"
        }
        do {
            try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive",
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return "failed to write \(plistURL.path): \(error.localizedDescription)"
        }
        // Ask launchd to pick it up now as well as at the next login.
        let status = runLaunchctl(["load", "-w", plistURL.path])
        return status == 0 ? "enabled (\(plistURL.path))" : "enabled, but launchctl load failed (code \(status))"
    }

    private static func disable() -> String {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return "not enabled"
        }
        _ = runLaunchctl(["unload", "-w", plistURL.path])
        do {
            try FileManager.default.removeItem(at: plistURL)
            return "disabled"
        } catch {
            return "failed to remove \(plistURL.path): \(error.localizedDescription)"
        }
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
