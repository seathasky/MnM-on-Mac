import Foundation

enum WineGamePreferences {
    private struct Snapshot {
        let prefix: URL
        let data: Data
        let modified: Date
    }

    static func settingsFile(in prefix: URL, user: String = NSUserName()) -> URL {
        prefix.appendingPathComponent("drive_c/users/\(user)/AppData/LocalLow/Niche Worlds Cult/Monsters and Memories/settings.json")
    }

    @discardableResult
    static func reconcile(into target: URL, prefixes: [URL], user: String = NSUserName()) throws -> URL? {
        let fm = FileManager.default
        func modified(_ url: URL) -> Date? {
            (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        func valid(_ url: URL) -> Data? {
            guard let data = try? Data(contentsOf: url), data.count < 1_000_000,
                  (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return nil }
            return data
        }
        let destination = settingsFile(in: target, user: user)
        let targetPath = target.standardizedFileURL.path
        var visited = Set<String>()
        let candidates = ([target] + prefixes).compactMap { prefix -> Snapshot? in
            guard visited.insert(prefix.standardizedFileURL.path).inserted else { return nil }
            let file = settingsFile(in: prefix, user: user)
            guard let date = modified(file), let data = valid(file) else { return nil }
            return Snapshot(prefix: prefix, data: data, modified: date)
        }
        guard let latest = candidates.max(by: { lhs, rhs in
            if lhs.modified != rhs.modified { return lhs.modified < rhs.modified }
            if lhs.prefix.standardizedFileURL.path == targetPath { return false }
            if rhs.prefix.standardizedFileURL.path == targetPath { return true }
            return lhs.prefix.path > rhs.prefix.path
        }), latest.prefix.standardizedFileURL.path != targetPath else { return nil }
        let data = latest.data
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            let existing = try Data(contentsOf: destination)
            if existing == data { return nil }
            let backup = destination.deletingLastPathComponent()
                .appendingPathComponent("settings.before-sync.\(UUID().uuidString).json")
            try existing.write(to: backup, options: .withoutOverwriting)
        }
        try data.write(to: destination, options: .atomic)
        try? fm.setAttributes([.modificationDate: latest.modified], ofItemAtPath: destination.path)
        return latest.prefix
    }
}
