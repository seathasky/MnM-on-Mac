//
//  GameRunState.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation
import Darwin

enum GameRunState {
    struct Status: Codable {
        let state: String
        let message: String
        let updated: TimeInterval
    }
    static func lockURL(_ paths: WinePaths) -> URL { paths.support.appendingPathComponent("game-session.lock") }
    static func statusURL(_ paths: WinePaths) -> URL { paths.support.appendingPathComponent("Logs/game-status.json") }

    static func acquire(_ paths: WinePaths) throws -> Int32 {
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        let descriptor = open(lockURL(paths).path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw PatcherSetupError.message("The game session could not be opened.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw PatcherSetupError.message("MnM is already running.")
        }
        return descriptor
    }
    static func release(_ descriptor: Int32) { _ = flock(descriptor, LOCK_UN); close(descriptor) }
    static func isRunning(_ paths: WinePaths) -> Bool {
        let descriptor = open(lockURL(paths).path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { _ = flock(descriptor, LOCK_UN); return false }
        return errno == EWOULDBLOCK
    }
    static func write(_ state: String, message: String, paths: WinePaths) {
        let file = statusURL(paths)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Status(state: state, message: message, updated: Date().timeIntervalSince1970))
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { }
    }
    static func read(_ paths: WinePaths) -> Status? {
        guard let data = try? Data(contentsOf: statusURL(paths)) else { return nil }
        return try? JSONDecoder().decode(Status.self, from: data)
    }
}
