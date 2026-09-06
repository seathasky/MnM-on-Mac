//
//  AppStorage.swift
//  MnM on Mac
//
//  Created by Matthew Centonze on 9/5/26.
//

import Foundation

enum AppStorage {
    static let name = "MnM on Mac"
    static let legacyName = "MnM on Mac Wine"
    static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }
    static var directory: URL { applicationSupport.appendingPathComponent(name, isDirectory: true) }
    static var officialLauncherDirectory: URL {
        applicationSupport.appendingPathComponent("com.monstersandmemories.mnm-patcher-app", isDirectory: true)
    }
    static var officialLauncherDatabase: URL { officialLauncherDirectory.appendingPathComponent("launcher.db") }
    static var requiresMigration: Bool {
        FileManager.default.fileExists(atPath: applicationSupport.appendingPathComponent(legacyName).path)
    }

    enum StorageError: LocalizedError {
        case conflict, unsupportedFolder
        var errorDescription: String? {
            switch self {
            case .conflict:
                return "Both MnM on Mac and MnM on Mac Wine folders exist in Application Support. Nothing was moved or overwritten. Resolve the duplicate folders, then reopen this app."
            case .unsupportedFolder:
                return "The app's Application Support location is not a regular folder. Nothing was moved."
            }
        }
    }

    @discardableResult
    static func prepare(in base: URL = applicationSupport) throws -> URL {
        let manager = FileManager.default
        let destination = base.appendingPathComponent(name, isDirectory: true)
        let legacy = base.appendingPathComponent(legacyName, isDirectory: true)
        func exists(_ url: URL) -> Bool {
            manager.fileExists(atPath: url.path) || (try? manager.destinationOfSymbolicLink(atPath: url.path)) != nil
        }
        func validate(_ url: URL) throws {
            guard exists(url) else { return }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw StorageError.unsupportedFolder }
        }
        try validate(destination)
        try validate(legacy)
        guard exists(legacy) else { return destination }
        guard !exists(destination) else { throw StorageError.conflict }

        let selection = legacy.appendingPathComponent("game-path.txt")
        var translatedSelection: String?
        if exists(selection) {
            let values = try selection.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw StorageError.unsupportedFolder }
            let saved = try String(contentsOf: selection, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            if saved.hasPrefix(legacy.path + "/") {
                translatedSelection = destination.path + saved.dropFirst(legacy.path.count) + "\n"
            }
        }
        try manager.moveItem(at: legacy, to: destination)
        do {
            if let translatedSelection = translatedSelection {
                try translatedSelection.write(to: destination.appendingPathComponent("game-path.txt"), atomically: true, encoding: .utf8)
            }
        } catch {
            try? manager.moveItem(at: destination, to: legacy)
            throw error
        }
        return destination
    }

    static func backupOfficialLauncherData() throws -> URL? {
        let manager = FileManager.default
        let source = officialLauncherDirectory
        guard manager.fileExists(atPath: source.path) else { return nil }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw StorageError.unsupportedFolder }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var backup = applicationSupport.appendingPathComponent("com.monstersandmemories.mnm-patcher-app.backup-\(formatter.string(from: Date()))", isDirectory: true)
        if manager.fileExists(atPath: backup.path) {
            backup = applicationSupport.appendingPathComponent("com.monstersandmemories.mnm-patcher-app.backup-\(UUID().uuidString)", isDirectory: true)
        }
        try manager.moveItem(at: source, to: backup)
        return backup
    }
}
