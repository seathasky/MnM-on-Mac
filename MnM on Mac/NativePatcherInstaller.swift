//
//  NativePatcherInstaller.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation

enum PatcherSetupError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

final class OfficialDownloadGuard: NSObject, URLSessionTaskDelegate {
    static func isAllowed(_ url: URL) -> Bool {
        let hosts = ["account.monstersandmemories.com", "pub-f06cad9ebbcd412bb0f4ff64f0f6a3d7.r2.dev"]
        return url.scheme == "https" && hosts.contains(url.host ?? "") &&
            (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.isAllowed) == true ? request : nil)
    }
}

private final class DownloadResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?
    func set(_ error: Error) { lock.lock(); defer { lock.unlock() }; stored = error }
    func get() -> Error? { lock.lock(); defer { lock.unlock() }; return stored }
}

struct NativePatcherInstaller {
    static let bundleName = "mnm_patcher_app.app"
    static let bundleID = "com.monstersandmemories.mnm-patcher-app"
    let toolsDirectory: URL

    static var defaultToolsDirectory: URL {
        AppStorage.directory.appendingPathComponent("Tools", isDirectory: true)
    }

    func install(progress: (String) -> Void) throws -> URL {
        let manager = FileManager.default
        let target = toolsDirectory.appendingPathComponent(Self.bundleName, isDirectory: true)
        if manager.isExecutableFile(atPath: target.appendingPathComponent("Contents/MacOS/mnm_launcher").path) {
            return target
        }
        try manager.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        let stage = toolsDirectory.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: stage) }

        progress("Downloading MnM patcher…")
        let metadata = stage.appendingPathComponent("update.json")
        let endpoint = URL(string: "https://account.monstersandmemories.com/api/launcher/update?target=darwin-aarch64&current_version=0.0.0")!
        var archiveURL = URL(string: "https://pub-f06cad9ebbcd412bb0f4ff64f0f6a3d7.r2.dev/launcher_v2/installer/Monsters%20%26%20Memories.app.tar.gz")!
        do {
            try Self.download(endpoint, to: metadata, maximumBytes: 524_288)
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any]
            if let value = object?["url"] as? String, let latest = URL(string: value), OfficialDownloadGuard.isAllowed(latest) {
                archiveURL = latest
            }
        } catch {
        }
        let archive = stage.appendingPathComponent("patcher.tar.gz")
        try Self.download(archiveURL, to: archive, maximumBytes: 209_715_200)
        progress("Setting up MnM patcher…")
        return try installArchive(archive)
    }

    func installArchive(_ archive: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        let names = try Self.command("/usr/bin/tar", ["-tzf", archive.path])
        let entries = names.split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.allSatisfy({ path in
            (path == Self.bundleName || path.hasPrefix(Self.bundleName + "/")) &&
            !path.split(separator: "/").contains("..") && !path.hasPrefix("/")
        }) else { throw PatcherSetupError.message("The official patcher download has an unexpected layout.") }
        let listing = try Self.command("/usr/bin/tar", ["-tvzf", archive.path])
        guard listing.split(separator: "\n").allSatisfy({ $0.first == "-" || $0.first == "d" }) else {
            throw PatcherSetupError.message("The patcher archive contains unsupported links or special files.")
        }

        let stage = toolsDirectory.appendingPathComponent(".extract-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: stage) }
        _ = try Self.command("/usr/bin/tar", ["-xzf", archive.path, "-C", stage.path, "--no-same-owner", "--no-same-permissions"])
        let extracted = stage.appendingPathComponent(Self.bundleName, isDirectory: true)
        let plist = extracted.appendingPathComponent("Contents/Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), options: [], format: nil) as? [String: Any]
        guard info?["CFBundleIdentifier"] as? String == Self.bundleID,
              info?["CFBundleExecutable"] as? String == "mnm_launcher",
              manager.isExecutableFile(atPath: extracted.appendingPathComponent("Contents/MacOS/mnm_launcher").path) else {
            throw PatcherSetupError.message("The download is not the expected native MnM patcher.")
        }

        do { _ = try Self.command("/usr/bin/codesign", ["--verify", "--deep", "--strict", extracted.path]) }
        catch { _ = try Self.command("/usr/bin/codesign", ["--force", "--sign", "-", extracted.path]) }
        _ = try Self.command("/usr/bin/codesign", ["--verify", "--deep", "--strict", extracted.path])

        let target = toolsDirectory.appendingPathComponent(Self.bundleName, isDirectory: true)
        if manager.fileExists(atPath: target.path) {
            let backup = toolsDirectory.appendingPathComponent("mnm_patcher_app.previous-\(UUID().uuidString).app")
            try manager.moveItem(at: target, to: backup)
            do { try manager.moveItem(at: extracted, to: target) }
            catch { try? manager.moveItem(at: backup, to: target); throw error }
        } else {
            try manager.moveItem(at: extracted, to: target)
        }
        return target
    }

    private static func download(_ url: URL, to destination: URL, maximumBytes: Int64) throws {
        guard OfficialDownloadGuard.isAllowed(url) else {
            throw PatcherSetupError.message("The patcher download did not come from an official MnM address.")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: OfficialDownloadGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let signal = DispatchSemaphore(value: 0)
        let result = DownloadResultBox()
        let task = session.downloadTask(with: url) { temporary, response, error in
            defer { signal.signal() }
            do {
                if let error = error { throw error }
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                      let finalURL = response.url, OfficialDownloadGuard.isAllowed(finalURL), let temporary = temporary else {
                    throw PatcherSetupError.message("The official MnM download server did not return a usable download.")
                }
                let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0, size <= maximumBytes else {
                    throw PatcherSetupError.message("The patcher download has an unexpected size.")
                }
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch { result.set(error) }
        }
        task.resume()
        guard signal.wait(timeout: .now() + 130) == .success else {
            task.cancel()
            throw PatcherSetupError.message("The patcher download timed out. Check your connection and try again.")
        }
        if let error = result.get() { throw error }
    }

    @discardableResult
    static func command(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PatcherSetupError.message("Patcher setup failed during \(URL(fileURLWithPath: executable).lastPathComponent) (code \(process.terminationStatus)).")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
