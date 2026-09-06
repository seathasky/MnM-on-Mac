//
//  WineRuntime.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation

struct WinePaths {
    let support: URL
    static var current: WinePaths {
        WinePaths(support: AppStorage.directory)
    }
    var runtime: URL { support.appendingPathComponent("Runtime/sikarugir-10.0_6-dxmt-0.80", isDirectory: true) }
    var engine: URL { runtime.appendingPathComponent("engine", isDirectory: true) }
    var libraries: URL { runtime.appendingPathComponent("Frameworks", isDirectory: true) }
    var setupLog: URL { support.appendingPathComponent("Logs/wine-setup.log") }
    var prefix: URL { support.appendingPathComponent("Prefix", isDirectory: true) }
    var game: URL { support.appendingPathComponent("Game/mnm", isDirectory: true) }
    var selectedGameFile: URL { support.appendingPathComponent("game-path.txt") }
    var prefixMarker: URL { prefix.appendingPathComponent(".mnm-runtime-ready") }

    var wine: URL? {
        for name in ["wine64", "wine"] {
            let candidate = engine.appendingPathComponent("bin/" + name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
    var wineLibrary: URL? {
        for name in ["lib/wine", "lib64/wine"] {
            let directory = engine.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("x86_64-windows/d3d11.dll").path),
               FileManager.default.fileExists(atPath: directory.appendingPathComponent("x86_64-unix/winemetal.so").path) {
                return directory
            }
        }
        return nil
    }
    var engineInstalled: Bool {
        wine != nil && wineLibrary != nil &&
        (try? String(contentsOf: runtime.appendingPathComponent("runtime-version.txt"), encoding: .utf8)) == WineRuntime.version
    }
    var librariesInstalled: Bool {
        FileManager.default.fileExists(atPath: libraries.appendingPathComponent("libinotify.0.dylib").path) &&
        (try? String(contentsOf: libraries.appendingPathComponent(".mnm-support-version"), encoding: .utf8)) == WineRuntime.supportVersion
    }
    var installed: Bool { engineInstalled && librariesInstalled }
    var initialized: Bool {
        installed && FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) &&
        (try? String(contentsOf: prefixMarker, encoding: .utf8)) == WineRuntime.version
    }
    var selectedGame: URL? {
        if let saved = try? String(contentsOf: selectedGameFile, encoding: .utf8) {
            let value = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("/") {
                let candidate = URL(fileURLWithPath: value, isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("mnm.exe").path) { return candidate }
            }
        }
        return FileManager.default.fileExists(atPath: game.appendingPathComponent("mnm.exe").path) ? game : nil
    }
}

enum WineRuntime {
    static let bundleIdentifier = "local.mnm.wine.desktop-launcher"
    static let version = "sikarugir-10.0_6-dxmt-0.80"
    static let supportVersion = "Template-1.0.11"
    static var rosettaAvailable: Bool { FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta") }
    static var readiness: String {
        let paths = WinePaths.current
        if AppStorage.requiresMigration { return "needs_storage_migration" }
        if !rosettaAvailable { return "needs_rosetta" }
        if paths.engineInstalled && !paths.librariesInstalled { return "needs_libraries" }
        if !paths.installed { return "needs_wine" }
        if !paths.initialized { return "needs_prefix" }
        if !GameSession.hasValidLogin { return "needs_login" }
        if paths.selectedGame == nil { return "needs_game" }
        return "ready"
    }

    static func environment(paths: WinePaths) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in Array(environment.keys) where key.hasPrefix("WINE") || key.hasPrefix("CX_") || key.hasPrefix("DYLD_") || key.hasPrefix("MNM_PLAY_") {
            environment.removeValue(forKey: key)
        }
        environment["WINEPREFIX"] = paths.prefix.path
        environment["WINEARCH"] = "win64"
        environment["WINEDEBUG"] = "-all"
        environment["WINEDLLOVERRIDES"] = "mscoree,mshtml=d;dxgi,d3d11,d3d10core=b"
        environment["PATH"] = paths.engine.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = [paths.libraries.path,
            paths.engine.appendingPathComponent("lib").path,
            paths.engine.appendingPathComponent("lib/wine/x86_64-unix").path,
            paths.engine.appendingPathComponent("lib/external").path, "/usr/lib"].joined(separator: ":")
        return environment
    }

    static func initialize(paths: WinePaths, progress: (String) -> Void) throws {
        guard rosettaAvailable else { throw PatcherSetupError.message("Rosetta is required to run this Wine engine. Install Apple's Rosetta, then try Set Up Wine again.") }
        guard paths.installed, let wine = paths.wine, let library = paths.wineLibrary else {
            throw PatcherSetupError.message("The Wine runtime is incomplete. Use Set Up Wine again.")
        }
        if paths.initialized { return }
        progress("Preparing the Windows environment…")
        try FileManager.default.createDirectory(at: paths.prefix, withIntermediateDirectories: true)
        let environment = environment(paths: paths)
        try runQuiet(wine, ["--version"], environment: environment, timeout: 30, step: "Check Wine", log: paths.setupLog)
        try runQuiet(wine, ["wineboot.exe", "--init"], environment: environment, timeout: 180, step: "Create Windows environment", log: paths.setupLog)
        try runQuiet(paths.engine.appendingPathComponent("bin/wineserver"), ["-w"], environment: environment, timeout: 180, step: "Wait for Windows setup", log: paths.setupLog)
        let system32 = paths.prefix.appendingPathComponent("drive_c/windows/system32")
        guard FileManager.default.fileExists(atPath: system32.path) else { throw PatcherSetupError.message("Wine did not finish creating its Windows environment.") }
        let metal = library.appendingPathComponent("x86_64-windows/winemetal.dll")
        let destination = system32.appendingPathComponent("winemetal.dll")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: metal, to: destination)
        try runQuiet(wine, ["reg.exe", "add", "HKCU\\Software\\Wine", "/v", "Version", "/d", "win10", "/f"], environment: environment, timeout: 60, step: "Configure Windows version", log: paths.setupLog)
        try version.write(to: paths.prefixMarker, atomically: true, encoding: .utf8)
    }

    static func runQuiet(_ executable: URL, _ arguments: [String], environment: [String: String], timeout: TimeInterval,
                         step: String = "Wine setup", log: URL? = nil) throws {
        var logHandle: FileHandle?
        if let log = log {
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: log.path) {
                FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: log)
            let size = try handle.seekToEnd()
            if size > 2_000_000 { try handle.truncate(atOffset: 0); try handle.seek(toOffset: 0) }
            try handle.write(contentsOf: Data("\n[\(Date())] \(step)\n".utf8))
            logHandle = handle
        }
        defer { try? logHandle?.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = logHandle ?? FileHandle.nullDevice
        process.standardError = logHandle ?? FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() }
        catch {
            try? logHandle?.write(contentsOf: Data((error.localizedDescription + "\n").utf8))
            throw PatcherSetupError.message("\(step) could not start. See Open Setup Log for details.")
        }
        guard finished.wait(timeout: .now() + timeout) == .success else {
            if process.isRunning { process.terminate() }
            throw PatcherSetupError.message("\(step) timed out. See Open Setup Log for details.")
        }
        guard process.terminationStatus == 0 else {
            throw PatcherSetupError.message("\(step) failed (code \(process.terminationStatus)). See Open Setup Log for the actual error.")
        }
    }
}

enum GameSession {
    private static var database: URL { AppStorage.officialLauncherDatabase }
    private static func query(_ sql: String) -> String? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", database.path, sql]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return nil }
    }
    private static func token() -> String? {
        query("SELECT value FROM settings WHERE variable='token' LIMIT 1;")
    }
    static func isValid(_ token: String, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = json["exp"] as? Double else { return false }
        return expiry > now + 60
    }
    static var hasValidLogin: Bool { token().map { isValid($0) } ?? false }
    static var hasRecordedInstallation: Bool {
        query("SELECT EXISTS(SELECT 1 FROM game_versions LIMIT 1);") == "1"
    }
    static func process(for arguments: [String], paths: WinePaths) throws -> Process {
        if arguments == ["--from-app"] { return try makeProcess(paths: paths) }
        guard arguments.count == 4, arguments[0] == "--from-patcher", arguments[2] == "--token" else {
            throw PatcherSetupError.message("The game launch request was not recognized.")
        }
        let requested = URL(fileURLWithPath: arguments[1]).resolvingSymlinksInPath()
        let candidates = [paths.game, paths.selectedGame].compactMap { $0 }
        guard candidates.contains(where: { $0.appendingPathComponent("mnm.exe").resolvingSymlinksInPath().path == requested.path }) else {
            throw PatcherSetupError.message("The launcher requested a game outside this app's configured installation.")
        }
        return try makeProcess(paths: paths, credential: arguments[3], gameDirectory: requested.deletingLastPathComponent())
    }
    static func makeProcess(paths: WinePaths, credential suppliedCredential: String? = nil, gameDirectory: URL? = nil) throws -> Process {
        guard paths.initialized, let wine = paths.wine else { throw PatcherSetupError.message("Use Set Up Wine first.") }
        guard let game = gameDirectory ?? paths.selectedGame else { throw PatcherSetupError.message("Install the game or choose its folder first.") }
        guard let credential = suppliedCredential ?? token(), isValid(credential) else { throw PatcherSetupError.message("Sign in again using Update / Log In.") }
        let process = Process()
        process.executableURL = wine
        process.currentDirectoryURL = game
        process.environment = WineRuntime.environment(paths: paths)
        process.arguments = [game.appendingPathComponent("mnm.exe").path, "--token", credential, "-force-d3d11"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
