import Foundation
@main enum MigrationTests {
    static func main() throws {
        guard AppStorage.applicationSupport.path.hasPrefix("/private/tmp/mnm-") else { fatalError("Tests require isolated storage") }
        let manager = FileManager.default
        try manager.createDirectory(at: AppStorage.officialLauncherDirectory, withIntermediateDirectories: true)
        let source = AppStorage.officialLauncherDatabase
        guard !manager.fileExists(atPath: source.path) else { fatalError("Use a fresh test directory") }
        let payload = try JSONSerialization.data(withJSONObject: ["exp":Date().timeIntervalSince1970+3600])
            .base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        let credential = "test." + payload + ".test"
        _ = try NativePatcherInstaller.command("/usr/bin/sqlite3", [source.path, """
            CREATE TABLE settings (variable TEXT PRIMARY KEY,value TEXT);
            CREATE TABLE game_versions (slug TEXT PRIMARY KEY,version TEXT);
            INSERT INTO settings VALUES ('username','test-user'),('token','\(credential)'),('remember','true');
            INSERT INTO game_versions VALUES ('mnm','test-version');
            """])
        let original = try Data(contentsOf: source)
        let destination = AppStorage.windowsLauncherDatabase
        try AppStorage.migrateLauncherDatabase(to: destination)
        let sourceAfterMigration = try Data(contentsOf: source)
        precondition(sourceAfterMigration == original, "Migration changed original database")
        let migration = try NativePatcherInstaller.command("/usr/bin/sqlite3", [destination.path, "SELECT count(*) FROM accounts WHERE username='test-user'; SELECT value FROM settings WHERE variable='active_account'; SELECT version FROM game_versions WHERE slug='mnm';"])
        precondition(migration == "1\ntest-user\ntest-version\n")
        precondition(GameSession.hasValidLogin, "New-format account lookup failed")
        let permissions = try manager.attributesOfItem(atPath: destination.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        _ = try NativePatcherInstaller.command("/usr/bin/sqlite3", [destination.path,"UPDATE settings SET value='updated-user' WHERE variable='active_account';"])
        let existing = try Data(contentsOf: destination)
        try AppStorage.migrateLauncherDatabase(to: destination)
        let afterRetry = try Data(contentsOf: destination)
        precondition(afterRetry == existing, "Retry overwrote existing Windows data")
        try AppStorage.resetLauncherState(database: destination)
        precondition(!GameSession.hasValidLogin, "Re-authentication retained a credential")
        let game = try NativePatcherInstaller.command("/usr/bin/sqlite3", [destination.path,"SELECT version FROM game_versions WHERE slug='mnm';"])
        precondition(game == "test-version\n", "Re-authentication erased installation state")
        let sourceAfterReset = try Data(contentsOf: source)
        precondition(sourceAfterReset == original, "Reset changed legacy backup source")
        let backups = try manager.contentsOfDirectory(at: AppStorage.directory.appendingPathComponent("LauncherBackups"), includingPropertiesForKeys: nil)
        precondition(backups.count == 1)
        let backedUpAccount = try NativePatcherInstaller.command("/usr/bin/sqlite3", [backups[0].path,"SELECT value FROM settings WHERE variable='active_account'; SELECT token FROM accounts WHERE username='test-user'; SELECT version FROM game_versions WHERE slug='mnm';"])
        precondition(backedUpAccount == "updated-user\n" + credential + "\ntest-version\n")
        try AppStorage.resetLauncherState(database: destination,resetInstallation:true)
        let count = try NativePatcherInstaller.command("/usr/bin/sqlite3", [destination.path,"SELECT count(*) FROM game_versions;"])
        precondition(count == "0\n")
        print("PASS: legacy snapshot preserved; accounts migrated; retries preserve data; credentials backed up; re-auth preserves installation state; explicit reset clears stale state")
    }
}
