//
//  GameModeController.swift
//  MnM on Mac
//
//  Game Mode command behavior adapted from the MIT-licensed MacGamingFix project:
//  https://github.com/evertjr/MacGamingFix
//

import Foundation

final class GameModeController {
    let isAvailable: Bool
    private(set) var isActive = false

    init() {
        isAvailable = Self.runXcrun(["-f", "gamepolicyctl"])
    }

    func activate() -> Bool {
        guard isAvailable else { return false }
        if isActive { return true }
        isActive = Self.runXcrun(["gamepolicyctl", "game-mode", "set", "on"])
        return isActive
    }

    func deactivate() {
        guard isAvailable, isActive else { return }
        _ = Self.runXcrun(["gamepolicyctl", "game-mode", "set", "auto"])
        isActive = false
    }

    private static func runXcrun(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
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
