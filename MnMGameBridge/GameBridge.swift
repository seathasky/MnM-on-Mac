//
//  GameBridge.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation
import Darwin

@main
enum GameBridge {
    static func main() {
        let paths = WinePaths.current
        // Acquire is the authoritative check; never silently succeed when
        // another bridge owns the session lock.
        let descriptor: Int32
        do { descriptor = try GameRunState.acquire(paths) }
        catch {
            GameRunState.write("failed", message: error.localizedDescription, paths: paths)
            exit(1)
        }
        defer { GameRunState.release(descriptor) }

        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            var sessionCredential: String?
            if arguments == ["--from-session"] {
                let data = FileHandle.standardInput.readData(ofLength: 16_001)
                guard !data.isEmpty, data.count <= 16_000, let text = String(data: data, encoding: .utf8) else {
                    throw PatcherSetupError.message("The official launcher's game session could not be received. Retry Play.")
                }
                sessionCredential = text
            }
            let process = try GameSession.process(for: arguments, paths: paths, sessionCredential: sessionCredential)
            sessionCredential = nil
            let terminalLog = ProcessInfo.processInfo.environment["MNM_TERMINAL_LOG"] == "1"
            var output: TerminalOutputLog?
            var outputPipe: Pipe?
            if terminalLog {
                let logURL = paths.support.appendingPathComponent("Logs/wine-live.log")
                let log = try TerminalOutputLog(url: logURL, credential: process.arguments?.last ?? "")
                output = log
                log.write("\n[Terminal Log started \(Date())]\n")
                let pipe = Pipe()
                outputPipe = pipe
                process.standardOutput = pipe
                process.standardError = pipe
                pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                    let data = fileHandle.availableData
                    if data.isEmpty { fileHandle.readabilityHandler = nil }
                    else { log.consume(data) }
                }
                openTerminalLog(logURL)
            }
            defer {
                outputPipe?.fileHandleForReading.readabilityHandler = nil
                output?.finish()
            }

            GameRunState.write("starting", message: "Starting MnM…", paths: paths)
            try process.run()
            GameRunState.write("running", message: "Game is running", paths: paths)
            process.waitUntilExit()
            let code = process.terminationStatus
            output?.write("\n[Terminal Log ended \(Date())] code=\(code)\n")
            let failureMessage: String
            if code == 53 {
                failureMessage = "Use Official Launcher's Install + Repair."
            } else {
                failureMessage = "The game stopped (code \(code)). Try Play again, or use the official launcher’s Install + Repair if it repeats."
            }
            GameRunState.write(code == 0 ? "finished" : "failed",
                               message: code == 0 ? "Game closed" : failureMessage, paths: paths)
            output?.finish()
            // The Windows launcher waits on this bridge's actual exit status.
            exit(code)

        } catch {
            GameRunState.write("failed", message: error.localizedDescription, paths: paths)
            exit(1)
        }
    }

    private static func openTerminalLog(_ logURL: URL) {
        let commandURL = logURL.deletingLastPathComponent().appendingPathComponent("open-wine-live-log.command")
        let escapedPath = logURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/zsh\nexec /usr/bin/tail -f '\(escapedPath)'\n"
        do {
            try script.write(to: commandURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: commandURL.path)
            let opener = Process()
            opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            opener.arguments = ["-a", "Terminal", commandURL.path]
            opener.standardOutput = FileHandle.nullDevice
            opener.standardError = FileHandle.nullDevice
            try opener.run()
        } catch { }
    }
}

// Opt-in Terminal Log capture. Keep enough bytes between reads to redact a
// credential even when it spans pipe chunks.
final class TerminalOutputLog {
    private let lock = NSLock()
    private let handle: FileHandle
    private let secret: Data
    private var pending = Data()
    private var closed = false
    private var written = 0
    private let limit = 2_000_000

    init(url: URL, credential: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        handle = try FileHandle(forWritingTo: url)
        if try handle.seekToEnd() > 2_000_000 {
            try handle.truncate(atOffset: 0)
        }
        secret = Data(credential.utf8)
    }
    func consume(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        pending.append(data)
        if !secret.isEmpty {
            let replacement = Data("[redacted]".utf8)
            var cursor = pending.startIndex
            while let range = pending.range(of: secret, in: cursor..<pending.endIndex) {
                pending.replaceSubrange(range, with: replacement)
                cursor = range.lowerBound + replacement.count
            }
        }
        let count = max(0, pending.count - max(0, secret.count - 1))
        append(Data(pending.prefix(count)))
        pending.removeFirst(count)
    }
    func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        append(Data(message.utf8))
    }
    private func append(_ data: Data) {
        guard written < limit else { return }
        let bytes = Data(data.prefix(limit - written))
        try? handle.write(contentsOf: bytes)
        written += bytes.count
    }
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        append(pending)
        pending.removeAll()
        closed = true
        try? handle.close()
    }
}
