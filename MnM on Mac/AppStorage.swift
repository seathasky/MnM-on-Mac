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
        #if DEBUG
        if Bundle.main.bundleURL.path.hasPrefix("/private/tmp/mnm-updater-test-") {
            return Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("TestData", isDirectory: true)
        }
        if let test = ProcessInfo.processInfo.environment["MNM_TEST_APPLICATION_SUPPORT"],
           test.hasPrefix("/private/tmp/mnm-"), !test.contains("..") {
            return URL(fileURLWithPath: test, isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }
    static var directory: URL { applicationSupport.appendingPathComponent(name, isDirectory: true) }
    static var officialLauncherDirectory: URL {
        applicationSupport.appendingPathComponent("com.monstersandmemories.mnm-patcher-app", isDirectory: true)
    }
    static var officialLauncherDatabase: URL { officialLauncherDirectory.appendingPathComponent("launcher.db") }
    static var windowsLauncherDirectory: URL { directory.appendingPathComponent("Game", isDirectory: true) }
    static var windowsLauncherDatabase: URL { windowsLauncherDirectory.appendingPathComponent("launcher.db") }

    static func resetLauncherState(database: URL, resetInstallation: Bool = false) throws {
        if database == officialLauncherDatabase {
            _ = try backupOfficialLauncherData()
            return
        }
        let manager = FileManager.default
        guard manager.fileExists(atPath: database.path) else { return }
        let backups = directory.appendingPathComponent("LauncherBackups", isDirectory: true)
        try manager.createDirectory(at: backups, withIntermediateDirectories: true)
        let backup = backups.appendingPathComponent("launcher-\(UUID().uuidString).db")
        func run(_ path: URL, _ command: String, readOnly: Bool = false) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = (readOnly ? ["-readonly"] : []) + [path.path, command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw StorageError.launcherMigration }
        }
        let quoted = "'" + backup.path.replacingOccurrences(of: "'", with: "''") + "'"
        try run(database, ".backup \(quoted)", readOnly: true)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        let installation = resetInstallation ? "DELETE FROM game_versions;" : ""
        try run(database, """
            BEGIN IMMEDIATE;
            CREATE TABLE IF NOT EXISTS accounts (username TEXT PRIMARY KEY, token TEXT NOT NULL);
            DELETE FROM accounts;
            DELETE FROM settings WHERE variable IN ('token','username','active_account');
            \(installation)
            COMMIT;
            """)
    }

    // Migrate a consistent SQLite snapshot, never the game folder or Wine prefix.
    // The original database remains available for rollback and older app builds.
    static func migrateLauncherDatabase(to destination: URL) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path),
              manager.fileExists(atPath: officialLauncherDatabase.path) else { return }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".launcher-migration-\(UUID().uuidString).db")
        defer { try? manager.removeItem(at: stage) }
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "''") + "'" }
        func sqlite(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw StorageError.launcherMigration
            }
        }
        try sqlite(["-readonly", officialLauncherDatabase.path, ".backup \(quote(stage.path))"])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stage.path)
        // The newer Windows launcher stores per-account credentials rather than
        // the legacy single-token setting. Copy within SQLite, not command args.
        try sqlite([stage.path, """
            BEGIN IMMEDIATE;
            CREATE TABLE IF NOT EXISTS accounts (username TEXT PRIMARY KEY, token TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS account_aliases (username TEXT PRIMARY KEY, alias TEXT NOT NULL);
            INSERT OR IGNORE INTO accounts (username,token)
                SELECT u.value,t.value FROM settings u,settings t
                WHERE u.variable='username' AND t.variable='token'
                    AND length(u.value)>0 AND length(t.value)>0;
            INSERT OR IGNORE INTO settings (variable,value)
                SELECT 'active_account',value FROM settings
                WHERE variable='username' AND length(value)>0;
            COMMIT;
            """])
        // No replacement of an existing Windows database, even on retry.
        guard !manager.fileExists(atPath: destination.path) else { return }
        try manager.moveItem(at: stage, to: destination)
    }
    static var requiresMigration: Bool {
        FileManager.default.fileExists(atPath: applicationSupport.appendingPathComponent(legacyName).path)
    }

    enum StorageError: LocalizedError {
        case conflict, rendererPrefixConflict(String), unsupportedFolder, launcherMigration
        var errorDescription: String? {
            switch self {
            case .conflict:
                return "Both MnM on Mac and MnM on Mac Wine folders exist in Application Support. Nothing was moved or overwritten. Resolve the duplicate folders, then reopen this app."
            case .rendererPrefixConflict(let name):
                return "Both the old and new \(name) prefix folders exist. Nothing was overwritten. Resolve the duplicate folders, then reopen this app."
            case .unsupportedFolder:
                return "The app's Application Support location is not a regular folder. Nothing was moved."
            case .launcherMigration:
                return "The launcher sign-in data could not be upgraded. The original data was left unchanged."
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
