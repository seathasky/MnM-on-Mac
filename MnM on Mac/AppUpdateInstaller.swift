import Foundation

/// Stages a validated replacement beside the current app. Never deletes the
/// current app; the replacement helper keeps a recoverable previous copy.
struct AppUpdateInstaller {
    struct Prepared {
        let currentApp: URL
        let replacement: URL
        let previousApp: URL
        let directory: URL

        func script(waitingFor pid: Int32, reopen: Bool = true) -> String {
            func quote(_ value: String) -> String {
                "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
            }
            return """
            #!/bin/sh
            set -eu
            app=\(quote(currentApp.path))
            replacement=\(quote(replacement.path))
            previous=\(quote(previousApp.path))
            attempts=0
            while kill -0 \(pid) 2>/dev/null; do
                attempts=$((attempts + 1))
                if [ "$attempts" -ge 60 ]; then exit 1; fi
                sleep 1
            done
            [ -d "$app" ] && [ -d "$replacement" ] && [ ! -e "$previous" ]
            /bin/mv "$app" "$previous"
            if ! /bin/mv "$replacement" "$app"; then
                /bin/mv "$previous" "$app"
                exit 1
            fi
            \(reopen ? "/usr/bin/open \"$app\"" : ":")
            """
        }
    }

    static func prepare(archive: URL, currentApp: URL, expectedVersion: String) throws -> Prepared {
        let manager = FileManager.default
        guard currentApp.isFileURL, currentApp.pathExtension == "app",
              manager.fileExists(atPath: currentApp.appendingPathComponent("Contents/Info.plist").path),
              let current = Bundle(url: currentApp), let identifier = current.bundleIdentifier else {
            throw failure("The current app could not be identified.")
        }
        // Reject traversal before extracting. Bundle symlinks are checked below.
        let entries = try run("/usr/bin/unzip", ["-Z1", archive.path])
            .split(separator: "\n", omittingEmptySubsequences: true)
        guard !entries.isEmpty, entries.allSatisfy({ entry in
            !entry.hasPrefix("/") && !entry.contains("\\")
                && !entry.split(separator: "/").contains("..")
        }) else { throw failure("The update archive contains unsafe paths.") }

        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mnm-update-validation-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: temporary) }
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, temporary.path])
        var candidates: [URL] = []
        for item in try manager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            if item.pathExtension == "app" { candidates.append(item) }
            else if item.lastPathComponent != "__MACOSX",
                    try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
                    try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true {
                candidates += try manager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "app" }
            }
        }
        guard candidates.count == 1, let candidate = candidates.first,
              try candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              let bundle = Bundle(url: candidate), bundle.bundleIdentifier == identifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion,
              let executable = bundle.executableURL,
              executable.resolvingSymlinksInPath().path.hasPrefix(candidate.resolvingSymlinksInPath().path + "/"),
              manager.isExecutableFile(atPath: executable.path) else {
            throw failure("The download is not the expected MnM on Mac version.")
        }
        if let enumerator = manager.enumerator(at: candidate, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let item as URL in enumerator {
                if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true,
                   !item.resolvingSymlinksInPath().path.hasPrefix(candidate.resolvingSymlinksInPath().path + "/") {
                    throw failure("The update contains a link outside the app.")
                }
            }
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
        let currentTeam = try teamIdentifier(currentApp)
        if let currentTeam, try teamIdentifier(candidate) != currentTeam {
            throw failure("The update's developer signature does not match this app.")
        }
        let suffix = UUID().uuidString
        let parent = currentApp.deletingLastPathComponent()
        let directory = parent.appendingPathComponent(".\(currentApp.lastPathComponent).update-\(suffix)", isDirectory: true)
        let replacement = directory.appendingPathComponent(currentApp.lastPathComponent, isDirectory: true)
        let previous = parent.appendingPathComponent("\(currentApp.lastPathComponent).previous-\(suffix)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        do {
            _ = try run("/usr/bin/ditto", [candidate.path, replacement.path])
            _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", replacement.path])
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
        return Prepared(currentApp: currentApp, replacement: replacement,
                        previousApp: previous, directory: directory)
    }

    private static func teamIdentifier(_ app: URL) throws -> String? {
        let description = try run("/usr/bin/codesign", ["-d", "--verbose=4", app.path], captureError: true)
        let value = description.split(separator: "\n")
            .first { $0.hasPrefix("TeamIdentifier=") }.map { String($0.dropFirst(15)) }
        return value == "not set" ? nil : value
    }

    private static func run(_ tool: String, _ arguments: [String], captureError: Bool = false) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = captureError ? FileHandle.nullDevice : pipe
        process.standardError = captureError ? pipe : FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw failure("The update could not be validated or prepared.") }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "MnMAppUpdate", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message + " Your current app has not been changed."])
    }
}
