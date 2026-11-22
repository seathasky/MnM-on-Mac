import Foundation

@main struct WebViewLaunchScopeTest {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("mnm-webview-scope-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let paths = WinePaths(support: root)
        let app = root.appendingPathComponent("Fixture.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        let assets = resources.appendingPathComponent("LauncherCompatibilityAssets")
        let working = root.appendingPathComponent("Game")
        let installer = WindowsPatcherInstaller(paths: paths, workingDirectory: working, assets: assets)

        func write(_ file: URL, _ value: String) throws {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: file)
        }

        try write(installer.wine, "test Wine")
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: installer.wine.path)
        try write(installer.executable, "test official launcher")
        let bundledManifest = assets.appendingPathComponent("manifest.json")
        let installedManifest = installer.runtime.appendingPathComponent("installed-manifest.json")
        let fixtureManifest = URL(fileURLWithPath: "LauncherCompatibilityAssets/manifest.json")
        let fixtureRenderer = URL(fileURLWithPath: "LauncherNativeAssets/MnMLauncherRetina.dylib")
        let current = try String(contentsOf: fixtureManifest, encoding: .utf8)
        let manifest = try JSONSerialization.jsonObject(with: Data(current.utf8)) as! [String: Any]
        let files = manifest["files"] as! [String: String]
        let rendererDigest = files["MnMLauncherRetina.dylib"]!
        let windowsDigest = files["user32.dll"]!
        try write(bundledManifest, current)
        try write(installedManifest, current)
        let renderer = resources.appendingPathComponent("MnMLauncherRetina.dylib")
        try manager.copyItem(at: fixtureRenderer, to: renderer)
        let info = ["CFBundleIdentifier": "io.github.seathasky.mnmonmac.fixture",
                    "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL"]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = app.appendingPathComponent("Contents/MacOS/Fixture")
        try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[0]), to: executable)
        let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
        let environment = ProcessInfo.processInfo.environment
        try WineRuntime.runQuiet(codesign, ["--force", "--sign", "-", app.path],
                                 environment: environment, timeout: 15, step: "Sign test app")
        try write(working.appendingPathComponent(".mnm-windows-launcher-ready"), WindowsPatcherInstaller.version)
        let stamp = installer.prefix.appendingPathComponent(".mnm-launcher-display-ready")
        try write(stamp, "startup=4;retina=locked;dpi=192")
        try write(installer.prefix.appendingPathComponent("system.reg"), "registry")
        precondition(!installer.ready)
        try write(stamp, "startup=4;retina=locked;dpi=192;webview=" + WindowsPatcherInstaller.webViewArguments)
        precondition(installer.ready)

        let prior = current.replacingOccurrences(of: rendererDigest, with: String(repeating: "a", count: 64))
        try write(installedManifest, prior.replacingOccurrences(of: windowsDigest, with: String(repeating: "b", count: 64)))
        precondition(!installer.ready)
        try write(installedManifest, prior)
        precondition(installer.ready)

        let key = "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS"
        setenv(key, "--remote-debugging-port=9222", 1)
        precondition(installer.environment()[key] == nil)
        try WineRuntime.runQuiet(codesign, ["--force", "--sign", "-", "--identifier", "mnm.test.swapped-renderer", renderer.path],
                                 environment: environment, timeout: 15, step: "Re-sign test renderer")
        try WineRuntime.runQuiet(codesign, ["--verify", "--strict", "--all-architectures", renderer.path],
                                 environment: environment, timeout: 15, step: "Verify swapped test renderer")
        do {
            _ = try installer.makeProcess()
            fatalError("A renderer that breaks the app seal must be rejected")
        } catch {
            let unverified = try String(contentsOf: installedManifest, encoding: .utf8)
            precondition(unverified == prior)
        }

        try manager.removeItem(at: renderer)
        try manager.copyItem(at: fixtureRenderer, to: renderer)
        let launch = try installer.makeProcess()
        let validated = try String(contentsOf: installedManifest, encoding: .utf8)
        precondition(validated == current)
        let arguments = WindowsPatcherInstaller.webViewArguments.split(separator: " ")
        precondition(launch.environment?["WINEPREFIX"] == installer.prefix.path)
        precondition(launch.environment?[key] == nil)
        precondition(arguments.filter { $0 == "--no-sandbox" }.count == 1)
        precondition(arguments.contains("--disable-gpu"))
        precondition(arguments.contains("--disable-features=ForceSWDCompWhenDCompFallbackRequired,RemoveRedirectionBitmap"))
        precondition(!arguments.contains("--remote-debugging-port=9222"))
        precondition(ProcessInfo.processInfo.environment[key] == "--remote-debugging-port=9222")
        print("WebView2 startup checks passed: private Wine session, per-launcher flags, inherited switch filtering, signed renderer verification, and one-time compatibility refresh.")
    }
}
