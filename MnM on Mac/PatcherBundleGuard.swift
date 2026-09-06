//
//  PatcherBundleGuard.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation
import CryptoKit

enum PatcherBundleGuard {
    static let executableName = "MnMPatcherGuard"

    static func prepare(app: URL, guardExecutable: URL, bridgeExecutable: URL? = nil, redirectLibrary: URL? = nil) throws {
        let manager = FileManager.default
        let original = app.appendingPathComponent("Contents/MacOS/mnm_launcher")
        guard manager.isExecutableFile(atPath: original.path), manager.isExecutableFile(atPath: guardExecutable.path) else {
            throw PatcherSetupError.message("The patcher startup helper is missing. Restore the complete MnM on Mac app.")
        }
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), options: [], format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == NativePatcherInstaller.bundleID else {
            throw PatcherSetupError.message("The managed patcher has an unexpected identity.")
        }
        let destination = app.appendingPathComponent("Contents/MacOS/" + executableName)
        let expected = try Data(contentsOf: guardExecutable)
        let sourceHash = SHA256.hash(data: expected).map { String(format: "%02x", $0) }.joined()
        var companions: [(destination: URL, data: Data, key: String, hash: String)] = []
        guard (bridgeExecutable == nil) == (redirectLibrary == nil) else {
            throw PatcherSetupError.message("The Play redirect is incomplete. Restore the complete app.")
        }
        if let bridgeExecutable = bridgeExecutable, let redirectLibrary = redirectLibrary {
            for (source, relative, key) in [(bridgeExecutable, "Contents/MacOS/MnMGameBridge", "MNMBridgeSHA256"),
                                             (redirectLibrary, "Contents/Frameworks/MnMPlayRedirect.dylib", "MNMRedirectSHA256")] {
                let data = try Data(contentsOf: source)
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                companions.append((app.appendingPathComponent(relative), data, key, hash))
            }
        }
        if info["CFBundleExecutable"] as? String == executableName,
           info["MNMGuardSourceSHA256"] as? String == sourceHash,
           companions.allSatisfy({ info[$0.key] as? String == $0.hash && manager.fileExists(atPath: $0.destination.path) }),
           manager.isExecutableFile(atPath: destination.path),
           (try? NativePatcherInstaller.command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])) != nil {
            return
        }
        try expected.write(to: destination, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        for companion in companions {
            try manager.createDirectory(at: companion.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try companion.data.write(to: companion.destination, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: companion.destination.path)
            info[companion.key] = companion.hash
            _ = try NativePatcherInstaller.command("/usr/bin/codesign", ["--force", "--sign", "-", companion.destination.path])
        }
        info["CFBundleExecutable"] = executableName
        info["CFBundleDisplayName"] = companions.isEmpty ? "MnM Patcher — Update Only" : "MnM Launcher"
        info["MNMPlayRedirectEnabled"] = !companions.isEmpty
        info["MNMGuardSourceSHA256"] = sourceHash
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist, options: .atomic)
        _ = try NativePatcherInstaller.command("/usr/bin/codesign", ["--force", "--sign", "-", original.path])
        _ = try NativePatcherInstaller.command("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        _ = try NativePatcherInstaller.command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }
}
