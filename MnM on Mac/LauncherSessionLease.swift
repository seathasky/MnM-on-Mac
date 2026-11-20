import Foundation

final class LauncherSessionLease {
    private let file: URL
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "io.github.seathasky.mnmonmac.heartbeat", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var activity: NSObjectProtocol?

    init(directory: URL, interval: TimeInterval = 2) {
        file = directory.appendingPathComponent("heartbeat.txt")
        self.interval = interval
    }

    func start() {
        queue.sync {
            guard timer == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Keep the Monsters & Memories launcher session alive")
            renew()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
            source.setEventHandler { [weak self] in self?.renew() }
            timer = source
            source.resume()
        }
    }

    func stop() {
        queue.sync { cancelRenewal() }
    }

    private func renew() {
        guard (try? Data("running".utf8).write(to: file, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func cancelRenewal() {
        timer?.cancel()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    deinit { cancelRenewal() }
}
