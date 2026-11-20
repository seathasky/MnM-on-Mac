import Foundation

@main struct LauncherSessionLeaseTest {
    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("mnm-heartbeat-test-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let file = root.appendingPathComponent("heartbeat.txt")

        let heartbeat = LauncherSessionLease(directory: root, interval: 0.5)
        heartbeat.start()
        guard let first = modified(file) else { fatalError("heartbeat was not written on start") }
        let attributes = try manager.attributesOfItem(atPath: file.path)
        assert((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "heartbeat must be private")

        Thread.sleep(forTimeInterval: 2.0)
        guard let later = modified(file), later.timeIntervalSince(first) >= 1.0 else {
            fatalError("heartbeat stopped while the main thread was blocked")
        }

        heartbeat.stop()
        let stopped = modified(file)
        Thread.sleep(forTimeInterval: 1.2)
        assert(modified(file) == stopped, "heartbeat kept writing after stop")
        print("Launcher heartbeat tests passed (immediate, main thread blocked, private, stop).")
    }
}
