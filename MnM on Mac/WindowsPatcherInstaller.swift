import Foundation
import AppKit
import CryptoKit

/// A dedicated launcher runtime keeps compatibility changes out of game Wine
/// prefixes and graphics drivers. Both upgrades and first installs use this path.
struct WindowsPatcherInstaller {
    static let version = "mnm-webview2-1"
    static let installerURL = URL(string: "https://pub-f06cad9ebbcd412bb0f4ff64f0f6a3d7.r2.dev/launcher_v2/installer/Monsters%20%26%20Memories%20setup.exe")!
    let paths: WinePaths
    let workingDirectory: URL
    let assets: URL

    init(paths: WinePaths = .current, workingDirectory: URL? = nil, assets: URL? = nil) {
        self.paths = paths
        self.workingDirectory = workingDirectory ?? Self.workingDirectory(for: paths)
        self.assets = assets ?? Bundle.main.resourceURL!.appendingPathComponent("LauncherCompatibilityAssets", isDirectory: true)
    }
    static func workingDirectory(for paths: WinePaths) -> URL {
        if let game = paths.selectedGame, game.lastPathComponent == "mnm" { return game.deletingLastPathComponent() }
        return paths.game.deletingLastPathComponent()
    }
    var executable: URL { workingDirectory.appendingPathComponent("mnm_launcher.exe") }
    var runtime: URL { paths.runtime.appendingPathComponent("LauncherCompatibility", isDirectory: true) }
    var engine: URL { runtime.appendingPathComponent("engine", isDirectory: true) }
    var prefix: URL { paths.support.appendingPathComponent("Prefix-Launcher", isDirectory: true) }
    var wine: URL { engine.appendingPathComponent("bin/" + (paths.wine?.lastPathComponent ?? "wine")) }
    private var retinaRenderer: URL { assets.deletingLastPathComponent().appendingPathComponent("MnMLauncherRetina.dylib") }
    private var manifest: URL { assets.appendingPathComponent("manifest.json") }
    private var runtimeMarker: URL { runtime.appendingPathComponent("installed-manifest.json") }
    private var launcherMarker: URL { workingDirectory.appendingPathComponent(".mnm-windows-launcher-ready") }
    private var displayMarker: URL { prefix.appendingPathComponent(".mnm-launcher-display-ready") }
    // The launcher-only Cocoa bridge keeps Wine's 2x mapping stable across
    // resolution changes. Window fitting still uses live macOS usable bounds.
    private var launcherDPI: Int { 192 }
    private var displayConfiguration: String { "startup=4;retina=locked;dpi=192" }

    /// Distinguish first-time setup from a bundled compatibility refresh.
    /// An existing launcher can be updated quietly; this never skips `ready`
    /// validation or installation before launching the official executable.
    var hasExistingInstallation: Bool {
        paths.initialized &&
        FileManager.default.fileExists(atPath: executable.path) &&
        FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) &&
        (try? String(contentsOf: launcherMarker, encoding: .utf8)) == Self.version
    }

    var ready: Bool {
        guard let bundled = try? Data(contentsOf: manifest), !bundled.isEmpty else { return false }
        return FileManager.default.isExecutableFile(atPath: wine.path) &&
        FileManager.default.fileExists(atPath: executable.path) &&
        bundled == (try? Data(contentsOf: runtimeMarker)) &&
        (try? String(contentsOf: launcherMarker, encoding: .utf8)) == Self.version &&
        (try? String(contentsOf: displayMarker, encoding: .utf8)) == displayConfiguration &&
        FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path)
    }

    func environment() -> [String: String] {
        var result = WineRuntime.environment(paths: paths, graphicsBackend: .metal)
        // Never inherit development browser switches or debugging ports.
        for key in Array(result.keys) where key.hasPrefix("WEBVIEW2_") || key.hasPrefix("MNM_WEBVIEW_") {
            result.removeValue(forKey: key)
        }
        result["WINEPREFIX"] = prefix.path
        result["WINEDEBUG"] = "-all"
        result["PATH"] = engine.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        result["DYLD_FALLBACK_LIBRARY_PATH"] = [paths.libraries.path, engine.appendingPathComponent("lib").path,
            engine.appendingPathComponent("lib/wine/x86_64-unix").path, engine.appendingPathComponent("lib/external").path, "/usr/lib"].joined(separator: ":")
        result.removeValue(forKey: "WINEDLLPATH_PREPEND")
        return result
    }

    static func windowsPath(_ url: URL) throws -> String {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\\"), !url.path.contains("\"") else {
            throw PatcherSetupError.message("The launcher folder uses an unsupported filename.")
        }
        return "Z:" + url.path.replacingOccurrences(of: "/", with: "\\")
    }

    func makeProcess(controlsDirectory: URL? = nil, graphicsBackend: GraphicsBackend = .d3dMetal,
                     appVersion: String = "2.0.0", preparationStarted: TimeInterval? = nil) throws -> Process {
        guard ready else { throw PatcherSetupError.message("The Windows launcher needs its compatibility update first.") }
        let process = Process()
        process.executableURL = wine
        process.currentDirectoryURL = workingDirectory
        var launchEnvironment = environment()
        launchEnvironment["MNM_WEBVIEW_BRIDGE_SESSION"] = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        launchEnvironment["DYLD_INSERT_LIBRARIES"] = retinaRenderer.path
        launchEnvironment["MNM_LAUNCHER_RETINA_LOCK"] = "1"
        // Per-launch diagnostics contain compatibility stages only, never
        // account data or browser requests. Retain one prior attempt as well,
        // so automatic recovery does not erase the original failure evidence.
        let diagnostics = paths.support.appendingPathComponent("Logs/launcher-startup.log")
        try FileManager.default.createDirectory(at: diagnostics.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: diagnostics.path) {
            let prior = diagnostics.deletingLastPathComponent().appendingPathComponent("launcher-startup-previous.log")
            try Data(contentsOf: diagnostics).write(to: prior, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: prior.path)
        }
        var header = "MnM launcher startup diagnostics\n"
        if let started = preparationStarted {
            header += String(format: "native preparation before helper: %.3f seconds\n", ProcessInfo.processInfo.systemUptime - started)
        }
        try Data(header.utf8).write(to: diagnostics, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: diagnostics.path)
        launchEnvironment["MNM_LAUNCHER_DIAGNOSTICS"] = try Self.windowsPath(diagnostics)
        launchEnvironment["MNM_LAUNCHER_NATIVE_LOG"] = diagnostics.path
        if let controlsDirectory {
            launchEnvironment["MNM_WEBVIEW_FOOTER"] = "1"
            launchEnvironment["MNM_WEBVIEW_CONTROL_DIR"] = try Self.windowsPath(controlsDirectory)
            launchEnvironment["MNM_APP_VERSION"] = appVersion
            launchEnvironment["MNM_GRAPHICS_BACKEND"] = graphicsBackend.rawValue
            launchEnvironment["MNM_PLAY_HELPER"] = try Self.windowsPath(assets.appendingPathComponent("MnMWindowsLauncher.exe"))
            launchEnvironment["MNM_GAME_EXE"] = try Self.windowsPath(paths.selectedGame?.appendingPathComponent("mnm.exe") ?? workingDirectory.appendingPathComponent("mnm/mnm.exe"))
        }
        process.environment = launchEnvironment
        process.arguments = [assets.appendingPathComponent("MnMWindowsLauncher.exe").path,
                             try Self.windowsPath(executable), try Self.windowsPath(workingDirectory)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    /// Run off the main thread: Wine shutdown can take several seconds.
    /// Only the dedicated launcher prefix is reset; game sessions are untouched.
    func prepareLaunch() throws {
        // Wine returns 1 if this prefix has no server to stop. That is the
        // expected cold-launch case, not a failed compatibility setup.
        let server = engine.appendingPathComponent("bin/wineserver")
        try WineRuntime.runQuiet(server, ["-k"], environment: environment(), timeout: 15,
                                 step: "Close previous launcher session", log: paths.setupLog,
                                 allowedTerminationStatuses: [0, 1])
        try WineRuntime.runQuiet(server, ["-w"], environment: environment(), timeout: 15,
                                 step: "Wait for launcher session to close", log: paths.setupLog,
                                 allowedTerminationStatuses: [0, 1])
    }

    func requestClose(_ process: Process) {
        requestControl("--close", process: process)
    }

    func requestShow(_ process: Process) {
        requestControl("--show", process: process)
    }

    private func requestControl(_ command: String, process: Process) {
        guard let session = process.environment?["MNM_WEBVIEW_BRIDGE_SESSION"] else { return }
        let close = Process()
        close.executableURL = wine
        close.environment = environment()
        close.arguments = [assets.appendingPathComponent("MnMWindowsLauncher.exe").path, command, session]
        close.standardInput = FileHandle.nullDevice
        close.standardOutput = FileHandle.nullDevice
        close.standardError = FileHandle.nullDevice
        try? close.run()
    }

    func install(approveRosettaInstallation: () -> Bool = { false }, progress: @escaping (String) -> Void) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: manifest.path),
              let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any],
              object["version"] as? String == Self.version,
              let hashes = object["files"] as? [String: String] else {
            throw PatcherSetupError.message("This app is missing its Windows launcher compatibility files.")
        }
        for name in ["user32.dll", "ole32.dll", "MnMWebViewBridge.dll", "MnMWindowsLauncher.exe", "MnMLauncherRetina.dylib"] {
            guard let hash = hashes[name] else { throw PatcherSetupError.message("The launcher compatibility package is incomplete.") }
            if name == "MnMLauncherRetina.dylib" {
                try verifyRetinaRenderer(digest: hash)
            } else {
                try WineInstaller.verify(assets.appendingPathComponent(name), digest: hash)
            }
        }
        if !paths.initialized {
            try WineInstaller(paths: paths).install(approveRosettaInstallation: approveRosettaInstallation, progress: progress)
        }
        if (try? Data(contentsOf: manifest)) != (try? Data(contentsOf: runtimeMarker)) {
            progress("Updating launcher compatibility…")
            try installEngine()
        }
        try manager.createDirectory(at: prefix, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) {
            try WineRuntime.runQuiet(wine, ["wineboot.exe", "--init"], environment: environment(), timeout: 180,
                                     step: "Prepare launcher environment", log: paths.setupLog)
        }
        // WebView2's updater may keep background Wine services running. Waiting
        // for the whole server to exit is not a readiness test for this prefix.
        // Update the cached Wine DLLs in an existing launcher prefix as well.
        for name in ["user32.dll", "ole32.dll"] {
            let target = prefix.appendingPathComponent("drive_c/windows/system32/" + name)
            if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
            try manager.copyItem(at: assets.appendingPathComponent(name), to: target)
        }
        let flags = "--disable-gpu --disable-features=ForceSWDCompWhenDCompFallbackRequired,RemoveRedirectionBitmap"
        for view in ["32", "64"] {
            try WineRuntime.runQuiet(wine, ["reg.exe", "add", "HKLM\\Software\\Policies\\Microsoft\\Edge\\WebView2\\AdditionalBrowserArguments",
                                          "/v", "mnm_launcher.exe", "/t", "REG_SZ", "/d", flags, "/f", "/reg:" + view],
                                     environment: environment(), timeout: 60, step: "Configure launcher graphics", log: paths.setupLog)
        }
        // These settings belong only to the launcher's private Wine prefix.
        // Never change the game's display resolution, DPI, or graphics prefix.
        let displaySettings = [
            ("HKCU\\Software\\Wine\\Mac Driver", "RetinaMode", "REG_SZ", "y"),
            ("HKCU\\Control Panel\\Desktop", "LogPixels", "REG_DWORD", String(launcherDPI)),
            ("HKCU\\Control Panel\\Desktop", "Win8DpiScaling", "REG_DWORD", "1"),
            ("HKCU\\Control Panel\\Desktop", "FontSmoothing", "REG_SZ", "2"),
            ("HKCU\\Control Panel\\Desktop", "FontSmoothingType", "REG_DWORD", "2")
        ]
        for (key, name, type, value) in displaySettings {
            try WineRuntime.runQuiet(wine, ["reg.exe", "add", key, "/v", name, "/t", type, "/d", value, "/f"],
                environment: environment(), timeout: 60, step: "Configure launcher display", log: paths.setupLog)
        }
        // wineboot caches the display before the registry settings above exist.
        // Apply them in a new private launcher session, not the game's session.
        try restartLauncherEnvironment()
        // Wine's default Desktop points at the user's macOS Desktop. Keep all
        // NSIS shortcuts inside this private prefix instead.
        let shortcutDirectory = prefix.appendingPathComponent("drive_c/MnMLauncherDesktop", isDirectory: true)
        try manager.createDirectory(at: shortcutDirectory, withIntermediateDirectories: true)
        for key in ["HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Shell Folders",
                    "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders"] {
            try WineRuntime.runQuiet(wine, ["reg.exe", "add", key, "/v", "Desktop", "/t", "REG_SZ",
                                          "/d", "C:\\MnMLauncherDesktop", "/f"],
                                     environment: environment(), timeout: 60, step: "Keep launcher shortcuts private", log: paths.setupLog)
        }
        try manager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try AppStorage.migrateLauncherDatabase(to: workingDirectory.appendingPathComponent("launcher.db"))
        if !manager.fileExists(atPath: executable.path) || (try? String(contentsOf: launcherMarker, encoding: .utf8)) != Self.version {
            progress("Downloading MnM patcher…")
            let stage = runtime.appendingPathComponent(".installer-\(UUID().uuidString)", isDirectory: true)
            try manager.createDirectory(at: stage, withIntermediateDirectories: false)
            defer { try? manager.removeItem(at: stage) }
            let download = stage.appendingPathComponent("Monsters & Memories setup.exe")
            try NativePatcherInstaller.download(Self.installerURL, to: download, maximumBytes: 100_000_000)
            progress("Installing MnM patcher…")
            // NSIS /D paths containing spaces are not reliably preserved by
            // Wine's Unix-to-Windows argument quoting. Use the official default
            // install, then copy its unchanged, self-contained launcher binary.
            try WineRuntime.runQuiet(wine, [download.path, "/S"],
                                     environment: environment(), timeout: 600, step: "Install official Windows launcher", log: paths.setupLog)
            let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
            let candidates = ((try? manager.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? []).map {
                $0.appendingPathComponent("AppData/Local/Monsters & Memories/mnm_launcher.exe")
            }.filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values?.isRegularFile == true && values?.isSymbolicLink != true &&
                    url.resolvingSymlinksInPath().path.hasPrefix(prefix.resolvingSymlinksInPath().path + "/")
            }
            guard candidates.count == 1, let installed = candidates.first else {
                throw PatcherSetupError.message("The official Windows installer did not produce an unambiguous launcher.")
            }
            let staged = workingDirectory.appendingPathComponent(".mnm-launcher-\(UUID().uuidString).exe")
            try manager.copyItem(at: installed, to: staged)
            defer { try? manager.removeItem(at: staged) }
            if manager.fileExists(atPath: executable.path) {
                let previous = workingDirectory.appendingPathComponent("mnm_launcher.previous-\(UUID().uuidString).exe")
                try manager.moveItem(at: executable, to: previous)
                do { try manager.moveItem(at: staged, to: executable) }
                catch { try? manager.moveItem(at: previous, to: executable); throw error }
            } else { try manager.moveItem(at: staged, to: executable) }
        }
        guard manager.fileExists(atPath: executable.path) else {
            throw PatcherSetupError.message("The official installer did not create the Windows launcher.")
        }
        if !webViewInstalled {
            progress("Installing launcher browser support…")
            let download = runtime.appendingPathComponent(".webview-\(UUID().uuidString).exe")
            defer { try? manager.removeItem(at: download) }
            try NativePatcherInstaller.download(URL(string: "https://go.microsoft.com/fwlink/p/?LinkId=2124703")!,
                                                to: download, maximumBytes: 10_000_000, allowMicrosoft: true)
            try WineRuntime.runQuiet(wine, [download.path, "/silent", "/install"], environment: environment(), timeout: 1200,
                                     step: "Install Microsoft WebView2", log: paths.setupLog)
        }
        guard webViewInstalled else { throw PatcherSetupError.message("Microsoft WebView2 installation did not finish. Try the official launcher setup again.") }
        // NSIS/WebView2 setup can leave browser services and first-boot display
        // state alive. Do not launch the UI inside that installation session.
        progress("Finishing launcher setup…")
        try restartLauncherEnvironment()
        try displayConfiguration.write(to: displayMarker, atomically: true, encoding: .utf8)
        try Self.version.write(to: launcherMarker, atomically: true, encoding: .utf8)
    }

    private func restartLauncherEnvironment() throws {
        let server = engine.appendingPathComponent("bin/wineserver")
        // WINEPREFIX is explicitly Prefix-Launcher in environment(). No global
        // server operation and no game-prefix termination is permitted here.
        try WineRuntime.runQuiet(server, ["-k"], environment: environment(), timeout: 30,
                                 step: "Stop launcher setup session", log: paths.setupLog)
        try WineRuntime.runQuiet(server, ["-w"], environment: environment(), timeout: 60,
                                 step: "Finish launcher setup session", log: paths.setupLog)
    }

    private var webViewInstalled: Bool {
        let manager = FileManager.default
        let base = prefix.appendingPathComponent("drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application", isDirectory: true)
        return ((try? manager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []).contains {
            manager.fileExists(atPath: $0.appendingPathComponent("msedgewebview2.exe").path)
        }
    }

    private func verifyRetinaRenderer(digest: String) throws {
        let manager = FileManager.default
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mnm-retina-validation-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: temporary) }
        let original = retinaRenderer
        try WineRuntime.runQuiet(URL(fileURLWithPath: "/usr/bin/codesign"), ["--verify", "--strict", original.path],
                                 environment: ProcessInfo.processInfo.environment, timeout: 15,
                                 step: "Validate launcher renderer signature", log: paths.setupLog)
        let copy = temporary.appendingPathComponent("renderer.dylib")
        try manager.copyItem(at: original, to: copy)
        try WineRuntime.runQuiet(URL(fileURLWithPath: "/usr/bin/codesign"), ["--remove-signature", copy.path],
                                 environment: ProcessInfo.processInfo.environment, timeout: 15,
                                 step: "Validate launcher renderer code", log: paths.setupLog)
        let canonical = try LauncherRendererIntegrity.canonical(Data(contentsOf: copy))
        let actual = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        guard actual == digest else {
            throw PatcherSetupError.message("The launcher renderer checksum did not match. Rebuild or reinstall MnM on Mac.")
        }
    }

    private func installEngine() throws {
        let manager = FileManager.default
        let parent = runtime.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".launcher-engine-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: stage) }
        let copy = stage.appendingPathComponent("engine", isDirectory: true)
        // These backports were built for this exact engine. Refuse to mix them
        // with a different Wine ABI if a future runtime update changes it.
        let originals = [
            "user32.dll": "52b981363ba79a50bcbe92fab041640630ee77806d99dbe29eb759c624c1323a",
            "ole32.dll": "e830fc029eb4ebadd7b2ebd74b418742bbe643ab8abeab8118463b3803e9627c"
        ]
        for (name, hash) in originals {
            try WineInstaller.verify(paths.engine.appendingPathComponent("lib/wine/x86_64-windows/" + name), digest: hash)
        }
        try manager.copyItem(at: paths.engine, to: copy)
        for name in ["user32.dll", "ole32.dll"] {
            let target = copy.appendingPathComponent("lib/wine/x86_64-windows/" + name)
            guard manager.fileExists(atPath: target.path) else { throw PatcherSetupError.message("The installed Wine engine has an unexpected layout.") }
            try manager.removeItem(at: target)
            try manager.copyItem(at: assets.appendingPathComponent(name), to: target)
        }
        try manager.copyItem(at: manifest, to: stage.appendingPathComponent("installed-manifest.json"))
        if manager.fileExists(atPath: runtime.path) {
            let backup = parent.appendingPathComponent("LauncherCompatibility.previous-\(UUID().uuidString)", isDirectory: true)
            try manager.moveItem(at: runtime, to: backup)
            do { try manager.moveItem(at: stage, to: runtime) }
            catch { try? manager.moveItem(at: backup, to: runtime); throw error }
        } else { try manager.moveItem(at: stage, to: runtime) }
    }
}
