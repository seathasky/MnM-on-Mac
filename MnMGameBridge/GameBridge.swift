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
        if GameRunState.isRunning(paths) { return }
        let descriptor: Int32
        do { descriptor = try GameRunState.acquire(paths) }
        catch {
            GameRunState.write("failed", message: "The game session could not be opened. Close any running game and try again.", paths: paths)
            exit(1)
        }
        defer { GameRunState.release(descriptor) }

        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            let process = try GameSession.process(for: arguments, paths: paths)
            let terminalLog = ProcessInfo.processInfo.environment["MNM_TERMINAL_LOG"] == "1"
            var logHandle: FileHandle?
            var outputPipe: Pipe?
            if terminalLog {
                let logURL = AppStorage.directory.appendingPathComponent("Logs/wine-live.log")
                try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("\n[Terminal Log started \(Date())]\n".utf8))
                logHandle = handle
                let pipe = Pipe()
                outputPipe = pipe
                process.standardOutput = pipe
                process.standardError = pipe
                openTerminalLog(logURL)
                pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                    let data = fileHandle.availableData
                    guard !data.isEmpty else { return }
                    try? handle.write(contentsOf: data)
                }
            }

            GameRunState.write("starting", message: "Starting MnM…", paths: paths)
            try process.run()
            GameRunState.write("running", message: "Game is running", paths: paths)
            process.waitUntilExit()
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            try? logHandle?.write(contentsOf: Data("\n[Terminal Log ended \(Date())]\n".utf8))
            try? logHandle?.close()
            let code = process.terminationStatus
            GameRunState.write(code == 0 ? "finished" : "failed",
                               message: code == 0 ? "Game closed" : "The game stopped (code \(code)).", paths: paths)
        } catch {
            GameRunState.write("failed", message: error.localizedDescription, paths: paths)
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
