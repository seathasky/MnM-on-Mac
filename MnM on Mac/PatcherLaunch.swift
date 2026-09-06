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
    var arguments: [String] { ["--stinky-cheese"] }

    func makeProcess() -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = workingDirectoryURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["MNM_PATCH_WORKDIR"] = workingDirectoryURL.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
