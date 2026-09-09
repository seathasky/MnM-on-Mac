//
//  WineRuntime.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation

enum GraphicsBackend: String {
    case metal
    case dxvk
    case kosmicKrisp = "kosmickrisp"
    case d3dMetal = "d3dmetal"

    static var requested: GraphicsBackend {
        guard let value = ProcessInfo.processInfo.environment["MNM_GRAPHICS_BACKEND"] else { return .metal }
        return GraphicsBackend(rawValue: value) ?? .metal
    }
}

struct WinePaths {
    let support: URL
    static var current: WinePaths {
        WinePaths(support: AppStorage.directory)
    }
    var runtime: URL { support.appendingPathComponent("Runtime/sikarugir-10.0_6-dxmt-0.80", isDirectory: true) }
    var engine: URL { runtime.appendingPathComponent("engine", isDirectory: true) }
    var libraries: URL { runtime.appendingPathComponent("Frameworks", isDirectory: true) }
    var dxvk: URL { runtime.appendingPathComponent("Graphics/dxvk-macos-1.10.3", isDirectory: true) }
    var dxvkPrefix: URL { support.appendingPathComponent("Prefix-DXVK", isDirectory: true) }
    var kosmicKrispPrefix: URL { support.appendingPathComponent("Prefix-KosmicKrisp", isDirectory: true) }
    var kosmicKrispICD: URL { runtime.appendingPathComponent("Graphics/kosmickrisp_mesa_icd.json") }
    var d3dMetal: URL { runtime.appendingPathComponent("Graphics/d3dmetal-3.0", isDirectory: true) }
    var d3dMetalPrefix: URL { support.appendingPathComponent("Prefix-D3DMetal", isDirectory: true) }
    var graphicsLogs: URL { support.appendingPathComponent("Logs/DXVK", isDirectory: true) }
    var graphicsCache: URL { support.appendingPathComponent("Cache/DXVK", isDirectory: true) }
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
        librariesPresent &&
        (try? String(contentsOf: libraries.appendingPathComponent(".mnm-support-version"), encoding: .utf8)) == WineRuntime.supportVersion
    }
    var librariesPresent: Bool {
        FileManager.default.fileExists(atPath: libraries.appendingPathComponent("libinotify.0.dylib").path)
    }
    var dxvkInstalled: Bool {
        let required = ["dxgi.dll", "d3d11.dll", "d3d10core.dll"]
        return required.allSatisfy { FileManager.default.fileExists(atPath: dxvk.appendingPathComponent($0).path) } &&
        (try? String(contentsOf: dxvk.appendingPathComponent("version.txt"), encoding: .utf8)) == "dxvk-macos-1.10.3"
    }
    var d3dMetalInstalled: Bool {
        let required = [
            "wine/x86_64-windows/d3d11.dll",
            "wine/x86_64-windows/d3d12.dll",
            "wine/x86_64-windows/dxgi.dll",
            "wine/x86_64-unix/d3d11.so",
            "wine/x86_64-unix/dxgi.so",
            "external/libd3dshared.dylib",
            "external/D3DMetal.framework/Versions/A/D3DMetal"
        ]
        let compatibleVersions = ["d3dmetal-3.0-template-1.0.11", "d3dmetal-3.0-template-1.0.15"]
        let installedVersion = try? String(contentsOf: d3dMetal.appendingPathComponent("version.txt"), encoding: .utf8)
        return required.allSatisfy { FileManager.default.fileExists(atPath: d3dMetal.appendingPathComponent($0).path) } &&
        installedVersion.map(compatibleVersions.contains) == true
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
    static let supportVersion = "Template-1.0.15"
    static var rosettaAvailable: Bool { FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta") }
    static var readiness: String {
        let paths = WinePaths.current
        if AppStorage.requiresMigration { return "needs_storage_migration" }
        if !rosettaAvailable { return "needs_rosetta" }
        if paths.engineInstalled && paths.librariesPresent && !paths.librariesInstalled { return "needs_runtime_update" }
        if paths.engineInstalled && !paths.librariesInstalled { return "needs_libraries" }
        if !paths.installed { return "needs_wine" }
        if !paths.initialized { return "needs_prefix" }
        if !GameSession.hasValidLogin { return "needs_login" }
        if paths.selectedGame == nil { return "needs_game" }
        return "ready"
    }

    static func environment(paths: WinePaths, graphicsBackend: GraphicsBackend = .metal, showHUD: Bool = false, msyncEnabled: Bool = true, metalFXUpscaling: Bool = false) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in Array(environment.keys) where key.hasPrefix("WINE") || key.hasPrefix("CX_") || key.hasPrefix("DYLD_") || key.hasPrefix("VK_") || key.hasPrefix("DXMT_") || key.hasPrefix("MNM_PLAY_") || key.hasPrefix("MNM_GRAPHICS_") || key == "MNM_METALFX_UPSCALING" || key == "MNM_MSYNC" || key == "MNM_TERMINAL_LOG" || key == "MTL_HUD_ENABLED" {
            environment.removeValue(forKey: key)
        }
        switch graphicsBackend {
        case .metal: environment["WINEPREFIX"] = paths.prefix.path
        case .dxvk: environment["WINEPREFIX"] = paths.dxvkPrefix.path
        case .kosmicKrisp: environment["WINEPREFIX"] = paths.kosmicKrispPrefix.path
        case .d3dMetal: environment["WINEPREFIX"] = paths.d3dMetalPrefix.path
        }
        environment["WINEARCH"] = "win64"
        let terminalLogEnabled = ProcessInfo.processInfo.environment["MNM_TERMINAL_LOG"] == "1"
        environment["WINEDEBUG"] = terminalLogEnabled ? "+timestamp,+pid,+tid,+seh,+loaddll,+msync" : "-all"
        if msyncEnabled { environment["WINEMSYNC"] = "1" }
        switch graphicsBackend {
        case .metal:
            environment["WINEDLLOVERRIDES"] = "mscoree,mshtml=d;dxgi,d3d11,d3d10core=b"
            if metalFXUpscaling {
                environment["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = "1"
                environment["DXMT_CONFIG"] = "d3d11.metalSpatialUpscaleFactor=1.5;"
            }
        case .dxvk, .kosmicKrisp:
            environment["WINEDLLOVERRIDES"] = "mscoree,mshtml=d;dxgi,d3d11,d3d10core=n"
        case .d3dMetal:
            environment["WINEDLLOVERRIDES"] = "mscoree,mshtml=d;dxgi,d3d11=n,b"
        }
        environment["PATH"] = paths.engine.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        var fallbackLibraries = [paths.libraries.path,
            paths.engine.appendingPathComponent("lib").path,
            paths.engine.appendingPathComponent("lib/wine/x86_64-unix").path,
            paths.engine.appendingPathComponent("lib/external").path, "/usr/lib"]
        if graphicsBackend == .d3dMetal {
            let external = paths.d3dMetal.appendingPathComponent("external", isDirectory: true)
            fallbackLibraries.insert(external.path, at: 0)
            environment["WINEDLLPATH_PREPEND"] = paths.d3dMetal.appendingPathComponent("wine", isDirectory: true).path
            environment["CX_ACTIVE_GRAPHICS_BACKEND"] = "d3dmetal"
            environment["WINED3DMETAL"] = "1"
            environment["CX_D3DMETALPATH"] = external.path
            environment["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = external.appendingPathComponent("libd3dshared.dylib").path
            environment["CX_APPLEGPT_LIBD3DSHARED_PATH"] = external.appendingPathComponent("libd3dshared.dylib").path
        } else if graphicsBackend == .kosmicKrisp {
            environment["VK_DRIVER_FILES"] = paths.kosmicKrispICD.path
            environment["VK_ICD_FILENAMES"] = paths.kosmicKrispICD.path
        }
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = fallbackLibraries.joined(separator: ":")
        if graphicsBackend == .dxvk || graphicsBackend == .kosmicKrisp {
            environment["DXVK_LOG_LEVEL"] = "info"
            let variant = graphicsBackend == .kosmicKrisp ? "KosmicKrisp" : "DXVK"
            environment["DXVK_LOG_PATH"] = paths.graphicsLogs.appendingPathComponent(variant, isDirectory: true).path
            environment["DXVK_STATE_CACHE_PATH"] = paths.graphicsCache.appendingPathComponent(variant, isDirectory: true).path
            if showHUD { environment["DXVK_HUD"] = "version,devinfo,fps" }
        } else if showHUD {
            environment["MTL_HUD_ENABLED"] = "1"
        }
        return environment
    }

    static func prepareGraphicsBackend(_ backend: GraphicsBackend, paths: WinePaths) throws {
        guard backend != .metal else { return }
        if backend == .d3dMetal {
            try prepareD3DMetal(paths: paths)
            return
        }
        let manager = FileManager.default
        guard paths.dxvkInstalled else {
            throw PatcherSetupError.message("DXVK is not installed. Select it again from Graphics Backend.")
        }
        let usesKosmicKrisp = backend == .kosmicKrisp
        if usesKosmicKrisp {
            let driver = paths.libraries.appendingPathComponent("libvulkan_kosmickrisp.dylib")
            guard manager.fileExists(atPath: driver.path) else {
                throw PatcherSetupError.message("KosmicKrisp is missing from the installed Sikarugir support package.")
            }
            let manifest: [String: Any] = [
                "file_format_version": "1.0.1",
                "ICD": ["api_version": "1.4.359", "library_path": driver.path]
            ]
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try manager.createDirectory(at: paths.kosmicKrispICD.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: paths.kosmicKrispICD, options: .atomic)
        }
        let sourceSystem32 = paths.prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        guard manager.fileExists(atPath: sourceSystem32.path) else {
            throw PatcherSetupError.message("The Windows environment is incomplete. Set up Wine again.")
        }
        let managed = ["dxgi.dll", "d3d11.dll", "d3d10core.dll"]
        let markerValue = "\(WineRuntime.version)|dxvk-macos-1.10.3|macos-three-dll-restored"
        let targetPrefix = usesKosmicKrisp ? paths.kosmicKrispPrefix : paths.dxvkPrefix
        let markerName = usesKosmicKrisp ? ".mnm-kosmickrisp-ready" : ".mnm-dxvk-ready"

        func prefixIsReady() -> Bool {
            let marker = targetPrefix.appendingPathComponent(markerName)
            guard (try? String(contentsOf: marker, encoding: .utf8)) == markerValue else { return false }
            let system32 = targetPrefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
            return managed.allSatisfy {
                manager.contentsEqual(atPath: system32.appendingPathComponent($0).path,
                                      andPath: paths.dxvk.appendingPathComponent($0).path)
            }
        }
        if prefixIsReady() { return }

        let stageName = usesKosmicKrisp ? ".Prefix-KosmicKrisp" : ".Prefix-DXVK"
        let stage = paths.support.appendingPathComponent("\(stageName)-\(UUID().uuidString)", isDirectory: true)
        try manager.copyItem(at: paths.prefix, to: stage)
        var stageShouldBeRemoved = true
        defer { if stageShouldBeRemoved { try? manager.removeItem(at: stage) } }
        let system32 = stage.appendingPathComponent("drive_c/windows/system32", isDirectory: true)

        func replace(_ destination: URL, with source: URL) throws {
            let temporary = destination.deletingLastPathComponent()
                .appendingPathComponent(".mnm-\(destination.lastPathComponent)-\(UUID().uuidString)")
            try manager.copyItem(at: source, to: temporary)
            do {
                if manager.fileExists(atPath: destination.path) {
                    _ = try manager.replaceItemAt(destination, withItemAt: temporary)
                } else {
                    try manager.moveItem(at: temporary, to: destination)
                }
            } catch {
                try? manager.removeItem(at: temporary)
                throw error
            }
        }

        for name in managed {
            let destination = system32.appendingPathComponent(name)
            guard manager.fileExists(atPath: destination.path) else {
                throw PatcherSetupError.message("The Windows environment is missing \(name).")
            }
            try replace(destination, with: paths.dxvk.appendingPathComponent(name))
        }
        try markerValue.write(to: stage.appendingPathComponent(markerName), atomically: true, encoding: .utf8)
        let variant = usesKosmicKrisp ? "KosmicKrisp" : "DXVK"
        try manager.createDirectory(at: paths.graphicsLogs.appendingPathComponent(variant, isDirectory: true), withIntermediateDirectories: true)
        try manager.createDirectory(at: paths.graphicsCache.appendingPathComponent(variant, isDirectory: true), withIntermediateDirectories: true)

        if manager.fileExists(atPath: targetPrefix.path) {
            let old = paths.support.appendingPathComponent("\(stageName)-Previous-\(UUID().uuidString)", isDirectory: true)
            try manager.moveItem(at: targetPrefix, to: old)
            do {
                try manager.moveItem(at: stage, to: targetPrefix)
                stageShouldBeRemoved = false
                try? manager.removeItem(at: old)
            } catch {
                try? manager.moveItem(at: old, to: targetPrefix)
                throw error
            }
        } else {
            try manager.moveItem(at: stage, to: targetPrefix)
            stageShouldBeRemoved = false
        }
    }

    private static func prepareD3DMetal(paths: WinePaths) throws {
        let manager = FileManager.default
        guard paths.d3dMetalInstalled else {
            throw PatcherSetupError.message("D3DMetal is not installed. Select it again from Graphics.")
        }
        let sourceSystem32 = paths.prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        guard manager.fileExists(atPath: sourceSystem32.path) else {
            throw PatcherSetupError.message("The Windows environment is incomplete. Set up Wine again.")
        }
        let managed = ["dxgi.dll", "d3d11.dll"]
        let markerValue = "\(WineRuntime.version)|d3dmetal-3.0-template-1.0.15"
        let compatibleMarkerValues = [
            "\(WineRuntime.version)|d3dmetal-3.0-template-1.0.11",
            markerValue
        ]

        func prefixIsReady() -> Bool {
            let marker = paths.d3dMetalPrefix.appendingPathComponent(".mnm-d3dmetal-ready")
            guard let installedMarker = try? String(contentsOf: marker, encoding: .utf8),
                  compatibleMarkerValues.contains(installedMarker) else { return false }
            let system32 = paths.d3dMetalPrefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
            return managed.allSatisfy {
                manager.contentsEqual(
                    atPath: system32.appendingPathComponent($0).path,
                    andPath: paths.d3dMetal.appendingPathComponent("wine/x86_64-windows/\($0)").path
                )
            }
        }
        if prefixIsReady() { return }

        let stage = paths.support.appendingPathComponent(".Prefix-D3DMetal-\(UUID().uuidString)", isDirectory: true)
        try manager.copyItem(at: paths.prefix, to: stage)
        var stageShouldBeRemoved = true
        defer { if stageShouldBeRemoved { try? manager.removeItem(at: stage) } }
        let system32 = stage.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        for name in managed {
            let destination = system32.appendingPathComponent(name)
            guard manager.fileExists(atPath: destination.path) else {
                throw PatcherSetupError.message("The Windows environment is missing \(name).")
            }
            let temporary = system32.appendingPathComponent(".mnm-\(name)-\(UUID().uuidString)")
            try manager.copyItem(at: paths.d3dMetal.appendingPathComponent("wine/x86_64-windows/\(name)"), to: temporary)
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        }
        try markerValue.write(to: stage.appendingPathComponent(".mnm-d3dmetal-ready"), atomically: true, encoding: .utf8)

        if manager.fileExists(atPath: paths.d3dMetalPrefix.path) {
            let old = paths.support.appendingPathComponent(".Prefix-D3DMetal-Previous-\(UUID().uuidString)", isDirectory: true)
            try manager.moveItem(at: paths.d3dMetalPrefix, to: old)
            do {
                try manager.moveItem(at: stage, to: paths.d3dMetalPrefix)
                stageShouldBeRemoved = false
                try? manager.removeItem(at: old)
            } catch {
                try? manager.moveItem(at: old, to: paths.d3dMetalPrefix)
                throw error
            }
        } else {
            try manager.moveItem(at: stage, to: paths.d3dMetalPrefix)
            stageShouldBeRemoved = false
        }
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
        let graphicsBackend = GraphicsBackend.requested
        let msyncEnabled = ProcessInfo.processInfo.environment["MNM_MSYNC"] != "0"
        let showHUD = ProcessInfo.processInfo.environment["MNM_GRAPHICS_HUD"] == "1"
        let metalFXUpscaling = graphicsBackend == .metal && ProcessInfo.processInfo.environment["MNM_METALFX_UPSCALING"] == "1"
        try WineRuntime.prepareGraphicsBackend(graphicsBackend, paths: paths)
        let process = Process()
        process.executableURL = wine
        process.currentDirectoryURL = game
        process.environment = WineRuntime.environment(paths: paths, graphicsBackend: graphicsBackend, showHUD: showHUD, msyncEnabled: msyncEnabled, metalFXUpscaling: metalFXUpscaling)
        let graphicsAPIArgument = "-force-d3d11"
        // Put Unity's renderer switch immediately after the executable. The game
        // also parses its own --token argument, so keeping the engine flags first
        // avoids a launcher wrapper accidentally consuming them.
        let gameArguments = [game.appendingPathComponent("mnm.exe").path, graphicsAPIArgument, "--token", credential]
        process.arguments = gameArguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

}
