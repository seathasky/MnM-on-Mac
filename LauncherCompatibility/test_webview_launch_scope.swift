import Foundation

@main struct WebViewLaunchScopeTest {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("mnm-webview-scope-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let paths = WinePaths(support: root)
        let assets = root.appendingPathComponent("Assets")
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
        try manager.copyItem(at: fixtureRenderer, to: root.appendingPathComponent("MnMLauncherRetina.dylib"))
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
        print("WebView2 startup checks passed: private Wine session, per-launcher flags, inherited switch filtering, and one-time compatibility refresh.")
    }
}
