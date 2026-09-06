//
//  WineInstaller.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation
import CryptoKit

struct RuntimeAsset {
    let label: String
    let url: URL
    let sha256: String
    static let wine = RuntimeAsset(label: "Wine", url: URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz")!, sha256: "9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2")
    static let graphics = RuntimeAsset(label: "DXMT graphics", url: URL(string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz")!, sha256: "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d")
    static let libraries = RuntimeAsset(label: "Wine support libraries", url: URL(string: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz")!, sha256: "9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a")
}

final class RuntimeDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let progress: (String) -> Void
    let label: String
    let finished = DispatchSemaphore(value: 0)
    private var failure: Error?
    private var received = false
    private var lastPercent = -1
    private let maximumBytes: Int64 = 400_000_000
    init(destination: URL, label: String, progress: @escaping (String) -> Void) {
        self.destination = destination; self.label = label; self.progress = progress
    }
    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "") &&
        (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allowed) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumBytes || totalBytesExpectedToWrite > maximumBytes {
            failure = PatcherSetupError.message("The runtime download exceeds its expected size.")
            downloadTask.cancel()
            return
        }
        let percent = totalBytesExpectedToWrite > 0 ? Int(totalBytesWritten * 100 / totalBytesExpectedToWrite) : -1
        if percent != lastPercent {
            lastPercent = percent
            progress(percent >= 0 ? "Downloading \(label)… \(percent)%" : "Downloading \(label)…")
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
                  let url = response.url, Self.allowed(url) else { throw PatcherSetupError.message("The runtime server did not return a usable download.") }
            let size = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 && size <= maximumBytes else { throw PatcherSetupError.message("The runtime download has an unexpected size.") }
            try FileManager.default.moveItem(at: location, to: destination)
            received = true
        } catch { failure = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if failure == nil { failure = error }
        finished.signal()
    }
    func fetch(_ url: URL) throws {
        guard Self.allowed(url) else { throw PatcherSetupError.message("The runtime source is not approved.") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1200
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: url)
        task.resume()
        guard finished.wait(timeout: .now() + 1210) == .success else {
            task.cancel()
            throw PatcherSetupError.message("The runtime download timed out. Try Set Up Wine again.")
        }
        if let failure = failure { throw failure }
        guard received else { throw PatcherSetupError.message("The runtime download did not complete.") }
    }
}

struct WineInstaller {
    let paths: WinePaths
    func install(fetchVerified: ((RuntimeAsset, URL) throws -> Void)? = nil, progress: @escaping (String) -> Void) throws {
        guard WineRuntime.rosettaAvailable else { throw PatcherSetupError.message("Install Apple's Rosetta before setting up Wine.") }
        let manager = FileManager.default
        let fetch = fetchVerified ?? { asset, file in
            progress("Downloading \(asset.label)…")
            try RuntimeDownload(destination: file, label: asset.label, progress: progress).fetch(asset.url)
            progress("Verifying \(asset.label)…")
            try Self.verify(file, digest: asset.sha256)
        }
        if !paths.engineInstalled {
            try manager.createDirectory(at: paths.runtime.deletingLastPathComponent(), withIntermediateDirectories: true)
            let stage = paths.runtime.deletingLastPathComponent().appendingPathComponent(".download-\(UUID().uuidString)")
            try manager.createDirectory(at: stage, withIntermediateDirectories: false)
            defer { try? manager.removeItem(at: stage) }
            let wineArchive = stage.appendingPathComponent("wine.tar.xz")
            let graphicsArchive = stage.appendingPathComponent("dxmt.tar.gz")
            for (asset, file) in [(RuntimeAsset.wine, wineArchive), (RuntimeAsset.graphics, graphicsArchive)] {
                try fetch(asset, file)
            }
            progress("Installing Wine and graphics…")
            try installArchives(wine: wineArchive, graphics: graphicsArchive)
        }
        if !paths.librariesInstalled {
            let stage = paths.runtime.appendingPathComponent(".support-download-\(UUID().uuidString)")
            try manager.createDirectory(at: stage, withIntermediateDirectories: false)
            defer { try? manager.removeItem(at: stage) }
            let archive = stage.appendingPathComponent("support.tar.xz")
            let asset = RuntimeAsset.libraries
            try fetch(asset, archive)
            progress("Installing Wine support libraries…")
            try installLibraries(archive)
        }
        try WineRuntime.initialize(paths: paths, progress: progress)
    }

    func installLibraries(_ archive: URL) throws {
        let manager = FileManager.default
        let names = try NativePatcherInstaller.command("/usr/bin/tar", ["-tf", archive.path]).split(separator: "\n").map(String.init)
        let roots = Set(names.compactMap { name -> String? in
            guard let range = name.range(of: ".app/Contents/Frameworks/"),
                  !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { return nil }
            return String(name[..<range.upperBound])
        })
        guard roots.count == 1, let prefix = roots.first else {
            throw PatcherSetupError.message("The support archive does not contain one unambiguous Wine libraries folder.")
        }
        let children = Set(names.compactMap { name -> String? in
            guard name.hasPrefix(prefix), let child = name.dropFirst(prefix.count).split(separator: "/").first,
                  child != "renderer", child != ".", child != ".." else { return nil }
            return prefix + child
        }).sorted()
        guard !children.isEmpty else { throw PatcherSetupError.message("The support archive does not contain the expected Wine libraries.") }
        let stage = paths.runtime.appendingPathComponent(".support-extract-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: stage) }
        try Self.extract(archive, to: stage, members: children)
        let extracted = stage.appendingPathComponent(prefix)
        guard manager.fileExists(atPath: extracted.appendingPathComponent("libinotify.0.dylib").path) else {
            throw PatcherSetupError.message("Wine's required libinotify.0.dylib is missing from the support archive.")
        }
        try Self.validateLinks(in: extracted)
        try WineRuntime.supportVersion.write(to: extracted.appendingPathComponent(".mnm-support-version"), atomically: true, encoding: .utf8)
        if manager.fileExists(atPath: paths.libraries.path) {
            let backup = paths.runtime.appendingPathComponent("Frameworks.previous-\(UUID().uuidString)")
            try manager.moveItem(at: paths.libraries, to: backup)
            do { try manager.moveItem(at: extracted, to: paths.libraries) }
            catch { try? manager.moveItem(at: backup, to: paths.libraries); throw error }
        } else { try manager.moveItem(at: extracted, to: paths.libraries) }
    }

    static func verify(_ file: URL, digest: String) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == digest else { throw PatcherSetupError.message("The runtime checksum did not match. The download was not installed.") }
    }

    func installArchives(wine: URL, graphics: URL) throws {
        let manager = FileManager.default
        let parent = paths.runtime.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".assemble-\(UUID().uuidString)")
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: stage) }
        let wineFiles = stage.appendingPathComponent("wine-files")
        let graphicsFiles = stage.appendingPathComponent("graphics-files")
        try Self.extract(wine, to: wineFiles)
        try Self.extract(graphics, to: graphicsFiles)
        let engine = wineFiles.appendingPathComponent("wswine.bundle")
        guard manager.isExecutableFile(atPath: engine.appendingPathComponent("bin/wine64").path) ||
              manager.isExecutableFile(atPath: engine.appendingPathComponent("bin/wine").path),
              manager.isExecutableFile(atPath: engine.appendingPathComponent("bin/wineserver").path) else {
            throw PatcherSetupError.message("The upstream Wine archive layout is not supported by this build.")
        }
        guard let library = ["lib/wine", "lib64/wine"].map({ engine.appendingPathComponent($0) }).first(where: {
            manager.fileExists(atPath: $0.appendingPathComponent("x86_64-unix").path) && manager.fileExists(atPath: $0.appendingPathComponent("x86_64-windows").path)
        }) else { throw PatcherSetupError.message("Wine's 64-bit libraries could not be found.") }
        let all = try Self.files(in: graphicsFiles)
        for (name, architecture) in [("winemetal.so", "x86_64-unix"), ("winemetal.dll", "x86_64-windows"), ("d3d11.dll", "x86_64-windows"), ("dxgi.dll", "x86_64-windows")] {
            let candidates = all.filter { $0.lastPathComponent == name && ($0.pathComponents.contains(architecture) || $0.pathComponents.contains("x64")) }
            guard candidates.count == 1 else { throw PatcherSetupError.message("The graphics archive does not contain an unambiguous 64-bit \(name).") }
            let destination = library.appendingPathComponent(architecture + "/" + name)
            if manager.fileExists(atPath: destination.path) || (try? manager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
                try manager.removeItem(at: destination)
            }
            try manager.copyItem(at: candidates[0], to: destination)
        }
        let assembled = stage.appendingPathComponent("runtime")
        try manager.createDirectory(at: assembled, withIntermediateDirectories: false)
        try manager.moveItem(at: engine, to: assembled.appendingPathComponent("engine"))
        try manager.moveItem(at: graphicsFiles, to: assembled.appendingPathComponent("graphics-source"))
        try WineRuntime.version.write(to: assembled.appendingPathComponent("runtime-version.txt"), atomically: true, encoding: .utf8)
        if manager.fileExists(atPath: paths.runtime.path) {
            let backup = parent.appendingPathComponent("\(WineRuntime.version).previous-\(UUID().uuidString)")
            try manager.moveItem(at: paths.runtime, to: backup)
            do { try manager.moveItem(at: assembled, to: paths.runtime) }
            catch { try? manager.moveItem(at: backup, to: paths.runtime); throw error }
        } else { try manager.moveItem(at: assembled, to: paths.runtime) }
    }

    static func files(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return [] }
        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true && values.isSymbolicLink != true ? url : nil
        }
    }
    static func extract(_ archive: URL, to destination: URL, members: [String] = []) throws {
        let names = try NativePatcherInstaller.command("/usr/bin/tar", ["-tf", archive.path] + members).split(separator: "\n").map(String.init)
        guard !names.isEmpty, names.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else {
            throw PatcherSetupError.message("The runtime archive contains unsafe paths.")
        }
        let listing = try NativePatcherInstaller.command("/usr/bin/tar", ["-tvf", archive.path] + members)
        for line in listing.split(separator: "\n") {
            guard ["-", "d", "l", "h"].contains(String(line.prefix(1))) else { throw PatcherSetupError.message("The runtime archive contains special files.") }
            for separator in [" -> ", " link to "] {
                if let range = line.range(of: separator) {
                    let target = String(line[range.upperBound...])
                    let prefix = String(line[..<range.lowerBound])
                    guard !target.hasPrefix("/"), let member = names.sorted(by: { $0.count > $1.count }).first(where: { prefix.hasSuffix($0) }) else {
                        throw PatcherSetupError.message("The runtime archive contains an unsupported link target.")
                    }
                    let archiveRoot = URL(fileURLWithPath: "/mnm-archive-root", isDirectory: true)
                    let base = separator == " link to " ? archiveRoot : archiveRoot.appendingPathComponent(member).deletingLastPathComponent()
                    guard base.appendingPathComponent(target).standardizedFileURL.path.hasPrefix(archiveRoot.path + "/") else {
                        throw PatcherSetupError.message("The runtime archive contains an escaping link.")
                    }
                }
            }
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        _ = try NativePatcherInstaller.command("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path, "--no-same-owner", "--no-same-permissions"] + members)
        try validateLinks(in: destination)
    }

    private static func validateLinks(in destination: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
        let root = destination.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                guard file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else {
                    throw PatcherSetupError.message("A runtime link points outside its installation folder.")
                }
            }
        }
    }
}
