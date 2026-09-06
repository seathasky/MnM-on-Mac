//
//  PatcherGuard.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation
import Darwin

@main
enum PatcherGuard {
    static func main() {
        let manager = FileManager.default
        let original = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            .deletingLastPathComponent().appendingPathComponent("mnm_launcher")
        let support = AppStorage.directory
        var directory = support.appendingPathComponent("Game", isDirectory: true)
        if let override = ProcessInfo.processInfo.environment["MNM_PATCH_WORKDIR"], override.hasPrefix("/") {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else if let saved = try? String(contentsOf: support.appendingPathComponent("game-path.txt"), encoding: .utf8) {
            let game = URL(fileURLWithPath: saved.trimmingCharacters(in: .whitespacesAndNewlines))
            if game.lastPathComponent == "mnm", manager.fileExists(atPath: game.appendingPathComponent("mnm.exe").path) {
                directory = game.deletingLastPathComponent()
            }
        }
        do { try manager.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { exit(73) }
        guard manager.changeCurrentDirectoryPath(directory.path), manager.isExecutableFile(atPath: original.path) else { exit(72) }
        let bridge = original.deletingLastPathComponent().appendingPathComponent("MnMGameBridge")
        let library = original.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Frameworks/MnMPlayRedirect.dylib")
        if manager.isExecutableFile(atPath: bridge.path), manager.fileExists(atPath: library.path) {
            setenv("MNM_PLAY_BRIDGE", bridge.path, 1)
            setenv("MNM_PLAY_GAME", directory.appendingPathComponent("mnm/mnm.exe").path, 1)
            setenv("DYLD_INSERT_LIBRARIES", library.path, 1)
        }
        let values: [String] = [original.path, "--stinky-cheese"]
        let strings = values.map { value in value.withCString { strdup($0)! } }
        defer { strings.forEach { free($0) } }
        var arguments: [UnsafeMutablePointer<CChar>?] = strings.map { $0 } + [nil]
        execv(original.path, &arguments)
        exit(71)
    }
}
