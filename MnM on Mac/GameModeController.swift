//
//  GameModeController.swift
//  MnM on Mac
//
//  Game Mode command behavior adapted from the MIT-licensed MacGamingFix project:
//  https://github.com/evertjr/MacGamingFix
//

import Foundation

final class GameModeController {
    private let toolURL: URL?
    let isAvailable: Bool
    private(set) var isActive = false

    init() {
        toolURL = Self.findTool()
        isAvailable = toolURL != nil
    }

    func activate() -> Bool {
        guard isAvailable else { return false }
        if isActive { return true }
        isActive = Self.run(arguments: ["game-mode", "set", "on"], using: toolURL)
        return isActive
    }

    func deactivate() {
        guard isAvailable, isActive else { return }
        _ = Self.run(arguments: ["game-mode", "set", "auto"], using: toolURL)
        isActive = false
    }

    private static func findTool() -> URL? {
        let fullXcodeTool = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/usr/bin/gamepolicyctl")
        if FileManager.default.isExecutableFile(atPath: fullXcodeTool.path) { return fullXcodeTool }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["-f", "gamepolicyctl"]
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let path = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, FileManager.default.isExecutableFile(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    private static func run(arguments: [String], using toolURL: URL?) -> Bool {
        guard let toolURL else { return false }
        let process = Process()
        process.executableURL = toolURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
