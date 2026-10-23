import Foundation
import SQLite3

/// Imports the rules stored by Input Source Pro.
///
/// Input Source Pro keeps its configuration in a Core Data store; the
/// `ZAPPRULE` table maps a bundle id to an input source id in exactly the
/// composite `sourceID::modeID` form this app uses, so the rows can be lifted
/// straight across. The store is opened read-only — the original app's data is
/// never modified.
enum ISPImporter {
    static let defaultStorePath = "~/Library/Application Support/Input Source Pro/Main.sqlite"

    struct ImportResult {
        var imported: [AppRule] = []
        var skipped: [String] = []
    }

    /// Read the app rules from an Input Source Pro store.
    static func loadRules(from path: String = defaultStorePath) -> ImportResult {
        var result = ImportResult()
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            result.skipped.append("store not found at \(expanded)")
            return result
        }
        var database: OpaquePointer?
        let status = sqlite3_open_v2(expanded, &database, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK, let database else {
            result.skipped.append("cannot open \(expanded)")
            return result
        }
        defer { sqlite3_close(database) }

        let query = """
            SELECT ZBUNDLEID, ZBUNDLENAME, ZINPUTSOURCEID,
                   ZDORESTOREKEYBOARD, ZHIDEINDICATOR
            FROM ZAPPRULE
            WHERE ZREMOVED IS NULL OR ZREMOVED = 0
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            result.skipped.append("cannot read ZAPPRULE: \(String(cString: sqlite3_errmsg(database)))")
            return result
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bundleID = text(statement, 0), !bundleID.isEmpty else { continue }
            guard let sourceID = text(statement, 2), !sourceID.isEmpty else {
                result.skipped.append("\(bundleID): no input source")
                continue
            }
            result.imported.append(AppRule(
                bundleID: bundleID,
                bundleName: text(statement, 1) ?? bundleID,
                inputSourceID: sourceID,
                restoreKeyboard: number(statement, 3) == 1,
                hideIndicator: number(statement, 4) == 1
            ))
        }
        return result
    }

    /// Merge imported rules into the store, keeping existing entries.
    static func importInto(store: RuleStore, from path: String = defaultStorePath) -> ImportResult {
        let result = loadRules(from: path)
        guard !result.imported.isEmpty else { return result }
        store.update { config in
            for rule in result.imported {
                if let index = config.appRules.firstIndex(where: { $0.bundleID == rule.bundleID }) {
                    config.appRules[index] = rule
                } else {
                    config.appRules.append(rule)
                }
            }
        }
        return result
    }

    // MARK: - sqlite helpers

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private static func number(_ statement: OpaquePointer?, _ column: Int32) -> Int {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return 0 }
        return Int(sqlite3_column_int(statement, column))
    }
}
