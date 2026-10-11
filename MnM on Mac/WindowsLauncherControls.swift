import Foundation
import AppKit
import Darwin

/// An app-owned, per-launch command channel for the official window's footer.
/// UI files contain no credentials. Live game tokens use an authenticated
/// loopback channel and are discarded after each launch.
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
    let gameChannel: GameSessionChannel
    let directory: URL
    private let manager = FileManager.default
    private var lastState: String?
    private var lastHeartbeat = Date.distantPast

    init(support: URL = WinePaths.current.support) throws {
        gameChannel = try GameSessionChannel()
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
        // Fit to native usable bounds, converted to the launcher's locked 2x
        // Wine coordinates. Never use Wine's cached pre-change monitor area.
        let screens = NSScreen.screens
        let top = screens.first?.frame.maxY ?? 0
        let workAreas = screens.prefix(16).enumerated().map { index, screen in
            let frame = screen.visibleFrame
            return "work\(index)=\(Int(frame.minX * 2)),\(Int((top - frame.maxY) * 2)),\(Int(frame.width * 2)),\(Int(frame.height * 2))\n"
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

    func takeGameRequests() -> [GameSessionChannel.Request] { gameChannel.takeRequests() }

    func reportGame(_ ticket: String, exitCode: Int32? = nil) throws {
        guard Self.validGameTicket(ticket) else { return }
        let value = exitCode.map { "exit:\($0)" } ?? "started"
        let file = directory.appendingPathComponent("game-result-\(ticket).txt")
        try Data(value.utf8).write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Only remove this launch's own private command directory after it exits.
    func finish() {
        gameChannel.finish()
        try? manager.removeItem(at: directory)
    }
}

// A loopback-only, per-launch authenticated channel keeps unsaved login tokens
// in memory. The existing command/result files contain UI actions and tickets.
final class GameSessionChannel {
    struct Request {
        let ticket: String
        let credential: String
    }
    private final class Client {
        let source: DispatchSourceRead
        var data = Data()
        init(source: DispatchSourceRead) { self.source = source }
    }
    let port: UInt16
    let secret = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var source: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private var pending: [Request] = []
    private var seen: Set<String> = []
    private var finished = false

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw PatcherSetupError.message("The game session channel could not be opened.") }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var success = false
        defer { if !success { close(fd) } }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 4) == 0,
              fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
            throw PatcherSetupError.message("The game session channel could not listen on localhost.")
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard named == 0 else { throw PatcherSetupError.message("The game session channel has no local address.") }
        port = UInt16(bigEndian: address.sin_port)
        let listener = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        listener.setEventHandler { [weak self] in self?.acceptClients(fd) }
        listener.setCancelHandler { close(fd) }
        source = listener
        success = true
        listener.resume()
    }

    deinit {
        source?.cancel()
        for client in clients.values { client.source.cancel() }
    }

    private func acceptClients(_ listener: Int32) {
        guard !finished else { return }
        while true {
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { return }
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            guard clients.count < 4, fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { close(fd); continue }
            var suppressSIGPIPE: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &suppressSIGPIPE, socklen_t(MemoryLayout<Int32>.size))
            let input = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            let client = Client(source: input)
            clients[fd] = client
            input.setEventHandler { [weak self, weak client] in
                guard let self, let client, self.clients[fd] === client else { return }
                self.receive(fd, client: client)
            }
            input.setCancelHandler { close(fd) }
            input.resume()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak client] in
                guard let self, let client, self.clients[fd] === client else { return }
                self.disconnect(fd)
            }
        }
    }

    private func receive(_ fd: Int32, client: Client) {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = recv(fd, &bytes, bytes.count, 0)
        guard count > 0 else {
            if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK) { disconnect(fd) }
            return
        }
        client.data.append(contentsOf: bytes.prefix(count))
        guard client.data.count <= 17_000 else { disconnect(fd); return }
        guard client.data.filter({ $0 == 10 }).count >= 3 else { return }
        guard let text = String(data: client.data, encoding: .utf8) else { disconnect(fd); return }
        let fields = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[3].isEmpty, fields[0] == secret,
              WindowsLauncherControls.validGameTicket(String(fields[1])),
              fields[2].utf8.count <= 16_000, !fields[2].isEmpty,
              fields[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-=".contains($0)) }),
              pending.count < 16, !seen.contains(String(fields[1])) else { disconnect(fd); return }
        let ticket = String(fields[1])
        seen.insert(ticket)
        pending.append(Request(ticket: ticket, credential: String(fields[2])))
        // Only acknowledge after the request is safely held in memory.
        let ack = Array("ok\n".utf8)
        _ = ack.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        disconnect(fd)
    }

    private func disconnect(_ fd: Int32) { clients.removeValue(forKey: fd)?.source.cancel() }
    func takeRequests() -> [Request] {
        defer { pending.removeAll() }
        return pending
    }
    func finish() {
        finished = true
        source?.cancel()
        source = nil
        for client in clients.values { client.source.cancel() }
        clients.removeAll()
        pending.removeAll()
        seen.removeAll()
    }
}
