import Foundation

@main struct UpdateCleanupTest {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("mnm-cleanup-test-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        func app(_ name: String, version: String = "2.0.2", id: String = "test.mnm") throws -> URL {
            let url = root.appendingPathComponent(name)
            let contents = url.appendingPathComponent("Contents")
            try manager.createDirectory(at: contents, withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
            return url
        }
        func stage(contents: String?) throws -> URL {
            let url = root.appendingPathComponent(".MnM on Mac.app.update-" + UUID().uuidString)
            try manager.createDirectory(at: url, withIntermediateDirectories: false)
            if let contents { try Data().write(to: url.appendingPathComponent(contents)) }
            return url
        }
        let current = try app("MnM on Mac.app")
        let old = try app("MnM on Mac.app.previous-" + UUID().uuidString, version: "2.0.0")
        let newer = try app("MnM on Mac.app.previous-" + UUID().uuidString, version: "9.0.0")
        let other = try app("MnM on Mac.app.previous-" + UUID().uuidString, id: "other.app")
        let active = try app("MnM on Mac.app.previous-" + UUID().uuidString, version: "2.0.1")
        let malformed = try app("MnM on Mac.app.previous-not-a-uuid")
        let finished = try stage(contents: "install.sh")
        let empty = try stage(contents: nil)
        let pending = try stage(contents: "MnM on Mac.app")
        let link = root.appendingPathComponent("MnM on Mac.app.previous-" + UUID().uuidString)
        try manager.createSymbolicLink(at: link, withDestinationURL: old)
        var cleaned: [URL] = []
        let count = try AppUpdateInstaller.cleanupPreviousInstalls(currentApp: current, runningApps: [current, active]) {
            cleaned.append($0)
        }
        precondition(count == 3 && Set(cleaned.map(\.lastPathComponent)) == Set([old, finished, empty].map(\.lastPathComponent)))
        for preserved in [current, newer, other, active, malformed, pending, link] {
            precondition(!cleaned.contains(where: { $0.lastPathComponent == preserved.lastPathComponent }))
        }
        // Exercise actual recoverable moves inside the disposable fixture only.
        let recovery = root.appendingPathComponent("Recovery")
        try manager.createDirectory(at: recovery, withIntermediateDirectories: false)
        let moved = try AppUpdateInstaller.cleanupPreviousInstalls(currentApp: current, runningApps: [current, active]) {
            try manager.moveItem(at: $0, to: recovery.appendingPathComponent($0.lastPathComponent))
        }
        precondition(moved == 3 && manager.fileExists(atPath: recovery.appendingPathComponent(old.lastPathComponent).path))
        let again = try AppUpdateInstaller.cleanupPreviousInstalls(currentApp: current, runningApps: [current, active]) { _ in
            fatalError("Cleanup should be idempotent")
        }
        precondition(again == 0)
        let prepared = AppUpdateInstaller.Prepared(currentApp: current, replacement: pending.appendingPathComponent("MnM on Mac.app"), previousApp: old, directory: pending)
        let script = prepared.script(waitingFor: 1234, reopen: false)
        precondition(script.contains("/bin/mv \"$previous\" \"$app\""))
        precondition(!script.contains("/bin/rm"))
        print("Update cleanup tests passed: old backups, finished stages, active/newer/unrelated/symlink safety, pending updates, recoverable moves, repeat cleanup, rollback retained.")
    }
}
