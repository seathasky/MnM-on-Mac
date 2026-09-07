//
//  PatcherLaunch.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation

struct PatcherLaunchPlan {
    let executableURL: URL
    let workingDirectoryURL: URL
    let environmentOverrides: [String: String]
    var arguments: [String] { ["--stinky-cheese"] }

    init(executableURL: URL, workingDirectoryURL: URL, environmentOverrides: [String: String] = [:]) {
        self.executableURL = executableURL
        self.workingDirectoryURL = workingDirectoryURL
        self.environmentOverrides = environmentOverrides
    }

    func makeProcess() -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = workingDirectoryURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["MNM_PATCH_WORKDIR"] = workingDirectoryURL.path
        for (key, value) in environmentOverrides {
            environment[key] = value
        }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
