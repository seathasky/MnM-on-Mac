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
        case conflict, rendererPrefixConflict(String), unsupportedFolder
        var errorDescription: String? {
            switch self {
            case .conflict:
                return "Both MnM on Mac and MnM on Mac Wine folders exist in Application Support. Nothing was moved or overwritten. Resolve the duplicate folders, then reopen this app."
            case .rendererPrefixConflict(let name):
                return "Both the old and new \(name) prefix folders exist. Nothing was overwritten. Resolve the duplicate folders, then reopen this app."
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
        if exists(legacy) {
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
        }

        let rendererPrefixes = [
            ("D3DMetal", "Prefix-D3DMetal-Test", "Prefix-D3DMetal", ".mnm-d3dmetal-test-ready", ".mnm-d3dmetal-ready"),
            ("DXVK", "Prefix-DXVK-Test", "Prefix-DXVK", ".mnm-dxvk-test-ready", ".mnm-dxvk-ready"),
            ("KosmicKrisp", "Prefix-KosmicKrisp-Test", "Prefix-KosmicKrisp", ".mnm-kosmickrisp-test-ready", ".mnm-kosmickrisp-ready")
        ]
        for (label, oldName, newName, oldMarkerName, newMarkerName) in rendererPrefixes {
            let oldPrefix = destination.appendingPathComponent(oldName, isDirectory: true)
            let newPrefix = destination.appendingPathComponent(newName, isDirectory: true)
            if exists(oldPrefix) {
                try validate(oldPrefix)
                guard !exists(newPrefix) else { throw StorageError.rendererPrefixConflict(label) }
                try manager.moveItem(at: oldPrefix, to: newPrefix)
            }
            if exists(newPrefix) {
                try validate(newPrefix)
                let oldMarker = newPrefix.appendingPathComponent(oldMarkerName)
                let newMarker = newPrefix.appendingPathComponent(newMarkerName)
                if exists(oldMarker), !exists(newMarker) {
                    try manager.moveItem(at: oldMarker, to: newMarker)
                }
            }
        }
        pruneOfficialLauncherBackupsBestEffort(in: base)
        return destination
    }

    static func backupOfficialLauncherData(in base: URL = applicationSupport) throws -> URL? {
        let manager = FileManager.default
        let source = base.appendingPathComponent("com.monstersandmemories.mnm-patcher-app", isDirectory: true)
        guard manager.fileExists(atPath: source.path) else { return nil }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw StorageError.unsupportedFolder }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var backup = base.appendingPathComponent("com.monstersandmemories.mnm-patcher-app.backup-\(formatter.string(from: Date()))", isDirectory: true)
        if manager.fileExists(atPath: backup.path) {
            backup = base.appendingPathComponent("com.monstersandmemories.mnm-patcher-app.backup-\(UUID().uuidString)", isDirectory: true)
        }
        try manager.moveItem(at: source, to: backup)
        // Moving a folder preserves its old modification date. Stamp this
        // backup so UUID collision fallbacks can also be ordered correctly.
        try? manager.setAttributes([.modificationDate: Date()], ofItemAtPath: backup.path)
        pruneOfficialLauncherBackupsBestEffort(in: base)
        return backup
    }

    private static func pruneOfficialLauncherBackupsBestEffort(in base: URL) {
        do { try pruneOfficialLauncherBackups(in: base) }
        catch { NSLog("Could not prune official launcher backups: %@", error.localizedDescription) }
    }

    static func pruneOfficialLauncherBackups(in base: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: base.path) else { return }
        let prefix = "com.monstersandmemories.mnm-patcher-app.backup-"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.isLenient = false
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let entries = try manager.contentsOfDirectory(at: base, includingPropertiesForKeys: Array(keys))
        let backups: [(url: URL, date: Date)] = try entries.compactMap { url in
            guard url.lastPathComponent.hasPrefix(prefix) else { return nil }
            let suffix = String(url.lastPathComponent.dropFirst(prefix.count))
            let timestamp = formatter.date(from: suffix)
            let datedBackup = timestamp.map { formatter.string(from: $0) == suffix } == true
            guard datedBackup || UUID(uuidString: suffix) != nil else { return nil }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            // The name records when legacy backups were made; Finder's date
            // often reflects when the original launcher folder last changed.
            return (url, datedBackup ? timestamp! : (values.contentModificationDate ?? .distantPast))
        }
        let newestFirst = backups.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.url.lastPathComponent > $1.url.lastPathComponent
        }
        for backup in newestFirst.dropFirst(2) {
            try manager.removeItem(at: backup.url)
        }
    }
}
