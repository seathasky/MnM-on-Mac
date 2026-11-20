import Foundation

@main struct WineGamePreferencesTest {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mnm-settings-sync-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        func prefix(_ name: String, settings: String?, age: TimeInterval) throws -> URL {
            let p = root.appendingPathComponent(name)
            let file = WineGamePreferences.settingsFile(in: p, user: "tester")
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let settings {
                try Data(settings.utf8).write(to: file)
                try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
            }
            return p
        }
        let dxmt = try prefix("Prefix", settings: #"{"GameSettingTargetBackgroundFramerate":2}"#, age: 3600)
        let d3d = try prefix("Prefix-D3DMetal", settings: #"{"GameSettingTargetBackgroundFramerate":30}"#, age: 60)
        let dxvk = try prefix("Prefix-DXVK", settings: nil, age: 0)
        let all = [dxmt, d3d, dxvk]
        func read(_ p: URL) -> String? { try? String(contentsOf: WineGamePreferences.settingsFile(in: p, user: "tester"), encoding: .utf8) }

        let first = try WineGamePreferences.reconcile(into: dxmt, prefixes: all, user: "tester"); assert(first == d3d)
        assert(read(dxmt)?.contains(":30") == true)
        let destination = WineGamePreferences.settingsFile(in: dxmt, user: "tester")
        let backups = try fm.contentsOfDirectory(at: destination.deletingLastPathComponent(),
                                                 includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.before-sync.") }
        assert(backups.count == 1)
        let previous = try String(contentsOf: backups[0], encoding: .utf8)
        assert(previous.contains(":2"))
        let tied = try WineGamePreferences.reconcile(into: dxmt, prefixes: [d3d], user: "tester")
        assert(tied == nil)
        _ = try WineGamePreferences.reconcile(into: dxvk, prefixes: all, user: "tester")
        assert(read(dxvk)?.contains(":30") == true)
        let noop = try WineGamePreferences.reconcile(into: d3d, prefixes: all, user: "tester"); assert(noop == nil)
        try Data("{not json".utf8).write(to: WineGamePreferences.settingsFile(in: dxvk, user: "tester"))
        let bad = try WineGamePreferences.reconcile(into: dxmt, prefixes: all, user: "tester"); assert(bad == nil)
        assert(read(dxmt)?.contains(":30") == true)
        print("Game settings sync tests passed (newer wins, missing filled, no-op, malformed ignored).")
    }
}
