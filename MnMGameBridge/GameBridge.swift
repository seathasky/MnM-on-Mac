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

            GameRunState.write("starting", message: "Starting MnM…", paths: paths)
            try process.run()
            GameRunState.write("running", message: "Game is running", paths: paths)
            process.waitUntilExit()
            let code = process.terminationStatus
            GameRunState.write(code == 0 ? "finished" : "failed",
                               message: code == 0 ? "Game closed" : "The game stopped (code \(code)).", paths: paths)
        } catch {
            GameRunState.write("failed", message: error.localizedDescription, paths: paths)
        }
    }
}
