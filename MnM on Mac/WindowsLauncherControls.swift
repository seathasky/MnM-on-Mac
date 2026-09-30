import Foundation
import AppKit

/// An app-owned, per-launch command channel for the official window's footer.
/// Contains UI actions/settings only; credentials and rendered pixels never enter it.
final class WindowsLauncherControls {
    enum Action: String {
        case opened, ready, discord, updates, about, legal, options
        case appUpdate = "app-update"
        case gameFolder = "game-folder"
        case wineConfig = "wine-config"
        case wineRegistry = "wine-registry"
        case d3dMetal = "graphics:d3dmetal"
        case dxmt = "graphics:metal"
        case dxvk = "graphics:dxvk"
    }
    let directory: URL
    private let manager = FileManager.default
    private var lastState: String?
    private var lastHeartbeat = Date.distantPast

    init(support: URL = WinePaths.current.support) throws {
        directory = support.appendingPathComponent("LauncherSessions", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
    }

    func writeState(version: String, backend: GraphicsBackend, busy: Bool, updateAvailable: Bool, launcherScale: Int = 0) throws {
        guard version.count <= 24, version.allSatisfy({ $0.isNumber || $0 == "." }) else { return }
        if Date().timeIntervalSince(lastHeartbeat) >= 2 {
            let heartbeat = directory.appendingPathComponent("heartbeat.txt")
            try Data("running".utf8).write(to: heartbeat, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: heartbeat.path)
            lastHeartbeat = Date()
        }
        let scale = [0, 60, 70, 80, 90, 100, 125].contains(launcherScale) ? launcherScale : 0
        // Report current usable screen areas in macOS points, not backing
        // pixels or Wine's potentially cached pre-resolution-change work area.
        let screens = NSScreen.screens
        let top = screens.first?.frame.maxY ?? 0
        let workAreas = screens.prefix(16).enumerated().map { index, screen in
            let frame = screen.visibleFrame
            return "work\(index)=\(Int(frame.minX)),\(Int(top - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))\n"
        }.joined()
        let state = "version=\(version)\nbackend=\(backend.rawValue)\nbusy=\(busy ? 1 : 0)\nupdate=\(updateAvailable ? 1 : 0)\nscale=\(scale)\n" + workAreas
        guard state != lastState else { return }
        let file = directory.appendingPathComponent("state.txt")
        try Data(state.utf8).write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        lastState = state
    }

    func takeActions() -> [Action] {
        let files = (try? manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])) ?? []
        var actions: [Action] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(128) {
            guard file.lastPathComponent.hasPrefix("request-"), file.pathExtension == "msg",
                  let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  info.isRegularFile == true, info.isSymbolicLink != true,
                  let count = info.fileSize, count > 0, count <= 64 else { continue }
            if let data = try? Data(contentsOf: file), data.count <= 64,
               let text = String(data: data, encoding: .utf8), let action = Action(rawValue: text) {
                actions.append(action)
            }
            try? manager.removeItem(at: file)
        }
        return actions
    }

    static func validGameTicket(_ ticket: String) -> Bool {
        ticket.count == 32 && ticket.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    func takeGameRequests() -> [String] {
        let files = (try? manager.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])) ?? []
        return files.prefix(128).compactMap { file in
            let name = file.lastPathComponent
            guard name.hasPrefix("game-request-"), name.hasSuffix(".msg") else { return nil }
            let ticket = String(name.dropFirst(13).dropLast(4))
            guard Self.validGameTicket(ticket),
                  let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  info.isRegularFile == true, info.isSymbolicLink != true, info.fileSize == 4,
                  (try? Data(contentsOf: file)) == Data("play".utf8) else { return nil }
            try? manager.removeItem(at: file)
            return ticket
        }
    }

    func reportGame(_ ticket: String, exitCode: Int32? = nil) throws {
        guard Self.validGameTicket(ticket) else { return }
        let value = exitCode.map { "exit:\($0)" } ?? "started"
        let file = directory.appendingPathComponent("game-result-\(ticket).txt")
        try Data(value.utf8).write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Only remove this launch's own private command directory after it exits.
    func finish() { try? manager.removeItem(at: directory) }
}
