import Foundation

@main struct WineSessionCleanupTest {
    static func main() {
        let root = URL(fileURLWithPath: "/private/tmp/mnm-cleanup-test/Runtime")
        let base = root.path + "/sikarugir-game/engine/bin/"
        let launcher = root.path + "/sikarugir-game/LauncherCompatibility/engine/bin/"
        let old = root.path + "/sikarugir-old/LauncherCompatibility.previous-881D31B3-6FCE-4463-9D4A-FA5C06DB283B/engine/bin/"
        func job(_ pid: Int32, _ path: String, parent: Int32 = 1, user: UInt32 = 501, started: UInt64 = 100,
                 micros: UInt64 = 0) -> WineSessionCleanup.ProcessIdentity {
            .init(pid: pid, parent: parent, user: user, started: started, microseconds: micros, executable: path)
        }
        let oldClient = job(21, old + "wine")
        let gameClient = job(22, base + "wine")
        let gameServer = job(23, base + "wineserver")
        let launcherClient = job(24, launcher + "wine64-preloader")
        let launcherServer = job(25, launcher + "wineserver")
        let reused = job(26, old + "wine")
        let lateServer = job(27, old + "wineserver")
        let first = [oldClient, gameClient, gameServer, launcherClient, launcherServer, reused,
                     job(28, old + "wine", parent: 314), job(29, old + "wine", started: 181),
                     job(30, old + "wine", user: 502), job(31, "/Applications/Other Wine/bin/wine"),
                     job(32, old + "something-else"), job(33, root.path + "-other/sikarugir-old/engine/bin/wine")]

        func run(_ snapshots: [[WineSessionCleanup.ProcessIdentity]?]) -> [Int32] {
            var next = snapshots.makeIterator()
            var signaled: [Int32] = []
            let result = WineSessionCleanup.collect(runtimeRoot: root, user: 501, now: 200,
                snapshot: { next.next() ?? nil },
                read: { pid in
                    if pid == reused.pid { return job(pid, old + "wine", micros: 1) }
                    return first.first { $0.pid == pid }
                },
                terminate: { signaled.append($0); return true })
            precondition(result == signaled)
            return result
        }

        precondition(run([first, first]) == [oldClient.pid])
        precondition(run([first, first + [lateServer]]).isEmpty)
        precondition(run([first, nil]).isEmpty)
        precondition(run([first, first.filter { $0.pid != oldClient.pid }]).isEmpty)
        print("Wine session cleanup passed: active engines, unrelated apps, process age, PID reuse, and incomplete snapshots.")
    }
}
