import Darwin
import Foundation

nonisolated enum WineSessionCleanup {
    struct ProcessIdentity: Equatable {
        let pid: Int32
        let parent: Int32
        let user: UInt32
        let started: UInt64
        let microseconds: UInt64
        let executable: String
    }

    private struct WineExecutable {
        let engine: String
        let isServer: Bool
    }

    private static func classify(_ path: String, under root: String) -> WineExecutable? {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        let pieces = path.dropFirst(root.count + 1).split(separator: "/").map(String.init)
        guard (pieces.count == 4 || pieces.count == 5), pieces[0].hasPrefix("sikarugir-"),
              pieces[pieces.count - 3] == "engine", pieces[pieces.count - 2] == "bin",
              let name = pieces.last else { return nil }
        if pieces.count == 5, pieces[1] != "LauncherCompatibility" {
            let backup = "LauncherCompatibility.previous-"
            guard pieces[1].hasPrefix(backup),
                  UUID(uuidString: String(pieces[1].dropFirst(backup.count))) != nil else { return nil }
        }
        guard ["wine", "wine64", "wine-preloader", "wine64-preloader", "wineserver"].contains(name) else { return nil }
        return WineExecutable(engine: pieces.dropLast(2).joined(separator: "/"), isServer: name == "wineserver")
    }

    static func collect(runtimeRoot: URL, user: UInt32, now: UInt64,
                        snapshot: () -> [ProcessIdentity]?,
                        read: (Int32) -> ProcessIdentity?,
                        terminate: (Int32) -> Bool) -> [Int32] {
        let root = runtimeRoot.resolvingSymlinksInPath().standardizedFileURL.path
        func liveEngines(_ processes: [ProcessIdentity]) -> Set<String> {
            Set(processes.compactMap { process in
                guard process.user == user, let wine = classify(process.executable, under: root),
                      wine.isServer else { return nil }
                return wine.engine
            })
        }
        guard let first = snapshot() else { return [] }
        let active = liveEngines(first)
        let candidates = first.compactMap { process -> (ProcessIdentity, String)? in
            guard process.pid > 1, process.parent == 1, process.user == user,
                  process.started > 0, now >= process.started, now - process.started >= 30,
                  let wine = classify(process.executable, under: root),
                  !wine.isServer, !active.contains(wine.engine) else { return nil }
            return (process, wine.engine)
        }
        guard !candidates.isEmpty, let second = snapshot() else { return [] }
        let confirmed = Set(second.map(\.pid))
        let activeNow = liveEngines(second)
        return candidates.compactMap { process, engine in
            guard confirmed.contains(process.pid), !activeNow.contains(engine),
                  read(process.pid) == process, terminate(process.pid) else { return nil }
            return process.pid
        }
    }

    static func cleanup(runtimeRoot: URL) {
        let pids = collect(runtimeRoot: runtimeRoot, user: geteuid(), now: UInt64(Date().timeIntervalSince1970),
                           snapshot: snapshot, read: { readProcess($0) }, terminate: { kill($0, SIGTERM) == 0 })
        if !pids.isEmpty { NSLog("Asked %ld leftover MnM Wine processes to exit.", pids.count) }
    }

    private static func snapshot() -> [ProcessIdentity]? {
        let estimate = Int(proc_listallpids(nil, 0))
        guard estimate > 0, estimate <= 131_072 else { return nil }
        var pids = [Int32](repeating: 0, count: estimate + 256)
        let bytes = Int32(pids.count * MemoryLayout<Int32>.stride)
        let count = Int(pids.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, bytes) })
        guard count > 0, count < pids.count else { return nil }
        var unresolvedServer = false
        let processes = pids.prefix(count).compactMap { pid in
            pid > 1 ? readProcess(pid, unresolvedServer: { unresolvedServer = true }) : nil
        }
        return unresolvedServer ? nil : processes
    }

    private static func readProcess(_ pid: Int32, unresolvedServer: (() -> Void)? = nil) -> ProcessIdentity? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_pid == UInt32(pid), info.pbi_status != UInt32(SZOMB),
              info.pbi_uid == geteuid() else { return nil }
        var path = [CChar](repeating: 0, count: 4096)
        let count = path.withUnsafeMutableBufferPointer { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard count > 0 else {
            let name = withUnsafeBytes(of: info.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if name == "wineserver" { unresolvedServer?() }
            return nil
        }
        return ProcessIdentity(pid: pid, parent: Int32(info.pbi_ppid), user: info.pbi_uid,
                               started: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec,
                               executable: String(cString: path))
    }
}
