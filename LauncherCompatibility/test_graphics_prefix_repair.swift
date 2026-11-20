import Foundation

@main struct GraphicsPrefixRepairTest {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("mnm-graphics-repair-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let paths = WinePaths(support: root)
        let backups = root.appendingPathComponent("Graphics Prefix Backups")
        let uiPath = "drive_c/users/test/AppData/LocalLow/fixture-ui.json"
        let systemPath = "drive_c/windows/system32"
        let registry = Data("fixture registry".utf8)

        func put(_ value: Data, at file: URL) throws {
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try value.write(to: file)
        }

        func snapshots() throws -> [URL] {
            guard manager.fileExists(atPath: backups.path) else { return [] }
            return try manager.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        }

        try put(registry, at: paths.prefix.appendingPathComponent("system.reg"))
        try manager.createDirectory(at: paths.prefix.appendingPathComponent(systemPath), withIntermediateDirectories: true)
        let dxvkDLLs = ["dxgi.dll", "d3d11.dll", "d3d10core.dll"]
        for name in dxvkDLLs { try put(Data("DXVK \(name)".utf8), at: paths.dxvk.appendingPathComponent(name)) }
        try put(Data("dxvk-macos-1.10.3".utf8), at: paths.dxvk.appendingPathComponent("version.txt"))
        try put(Data("test driver".utf8), at: paths.libraries.appendingPathComponent("libvulkan_kosmickrisp.dylib"))
        for name in ["wine/x86_64-windows/d3d11.dll", "wine/x86_64-windows/d3d12.dll", "wine/x86_64-windows/dxgi.dll",
                     "wine/x86_64-unix/d3d11.so", "wine/x86_64-unix/dxgi.so", "external/libd3dshared.dylib",
                     "external/D3DMetal.framework/Versions/A/D3DMetal"] {
            try put(Data("D3DMetal \(name)".utf8), at: paths.d3dMetal.appendingPathComponent(name))
        }
        try put(Data(WineRuntime.d3dMetalVersion.utf8), at: paths.d3dMetal.appendingPathComponent("version.txt"))

        let cases: [(GraphicsBackend, URL, String)] = [
            (.d3dMetal, paths.d3dMetalPrefix, ".mnm-d3dmetal-ready"),
            (.dxvk, paths.dxvkPrefix, ".mnm-dxvk-ready"),
            (.kosmicKrisp, paths.kosmicKrispPrefix, ".mnm-kosmickrisp-ready")
        ]
        for (backend, prefix, marker) in cases {
            let before = try snapshots()
            try WineRuntime.prepareGraphicsBackend(backend, paths: paths)
            let ui = prefix.appendingPathComponent(uiPath)
            let markerFile = prefix.appendingPathComponent(marker)
            let originalMarker = try Data(contentsOf: markerFile)
            let customUI = Data([0x00, 0xDA, 0xFF]) + Data(backend.rawValue.utf8)
            try put(customUI, at: ui)
            try WineRuntime.prepareGraphicsBackend(backend, paths: paths)
            let afterHealthy = try snapshots()
            precondition(Set(afterHealthy) == Set(before))

            let graphicsDLL = prefix.appendingPathComponent(systemPath + "/dxgi.dll")
            let goodDLL = try Data(contentsOf: graphicsDLL)
            let stale = Data("stale marker".utf8)
            try put(stale, at: markerFile)
            try manager.removeItem(at: graphicsDLL)
            try WineRuntime.prepareGraphicsBackend(backend, paths: paths)
            let newBackup = try snapshots().filter { !before.contains($0) }
            precondition(newBackup.count == 1 && newBackup[0].lastPathComponent.hasPrefix(prefix.lastPathComponent + "-"))
            let repairedUI = try Data(contentsOf: ui)
            let backedUpUI = try Data(contentsOf: newBackup[0].appendingPathComponent(uiPath))
            let repairedMarker = try Data(contentsOf: markerFile)
            let backedUpMarker = try Data(contentsOf: newBackup[0].appendingPathComponent(marker))
            let repairedDLL = try Data(contentsOf: graphicsDLL)
            precondition(repairedUI == customUI && backedUpUI == customUI)
            precondition(repairedDLL == goodDLL && repairedMarker == originalMarker && backedUpMarker == stale)

            try manager.removeItem(at: graphicsDLL)
            try manager.createDirectory(at: graphicsDLL, withIntermediateDirectories: false)
            do {
                try WineRuntime.prepareGraphicsBackend(backend, paths: paths)
                fatalError("An unexpected DLL directory should block repair")
            } catch {
                let afterFailure = try snapshots()
                let intactUI = try Data(contentsOf: ui)
                let intactMarker = try Data(contentsOf: markerFile)
                precondition(Set(afterFailure) == Set(before + newBackup))
                precondition(intactUI == customUI && intactMarker == originalMarker)
                var stillDirectory: ObjCBool = false
                precondition(manager.fileExists(atPath: graphicsDLL.path, isDirectory: &stillDirectory)
                             && stillDirectory.boolValue)
            }
            print("PASS \(backend.rawValue) first setup, healthy prefix, stale/missing DLL repair, AppData backup, and failure safety")
        }
    }
}
