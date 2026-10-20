import AppKit
import UniformTypeIdentifiers
import Observation

enum TerminationResult {
    case success
    case protected
    case needsAdministrator
    case failure(String)
}

@MainActor
@Observable
final class ProcessStore {
    /// Killing these freezes or logs out the session.
    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "logd", "opendirectoryd", "MacPulse",
    ]

    private(set) var processes: [ProcessItem] = []
    private(set) var lastUpdated: Date?
    var isPaused = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isRefreshing = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPaused else { return }
                self.refresh()
            }
        }
    }

    var totalCPU: Double { processes.reduce(0) { $0 + $1.cpu } }
    var totalMemory: Int64 { processes.reduce(0) { $0 + $1.memoryBytes } }
    var topByCPU: [ProcessItem] { Array(processes.sorted { $0.cpu > $1.cpu }.prefix(6)) }
    var topByMemory: [ProcessItem] { Array(processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(6)) }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let snapshot = await Task.detached(priority: .utility) { ProcessReader.snapshot() }.value

            var apps: [pid_t: NSRunningApplication] = [:]
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                apps[app.processIdentifier] = app
            }

            processes = snapshot.map { item in
                guard let app = apps[item.pid] else { return item }
                var enriched = item
                enriched.isApp = true
                enriched.name = app.localizedName ?? item.name
                return enriched
            }
            lastUpdated = .now
            isRefreshing = false
        }
    }

    func terminate(_ item: ProcessItem, force: Bool) -> TerminationResult {
        if item.pid <= 1 || Self.protectedNames.contains(item.name) { return .protected }

        if let app = NSRunningApplication(processIdentifier: item.pid) {
            let accepted = force ? app.forceTerminate() : app.terminate()
            if accepted {
                refreshSoon()
                return .success
            }
        }

        if kill(item.pid, force ? SIGKILL : SIGTERM) == 0 {
            refreshSoon()
            return .success
        }

        let code = errno
        if code == EPERM { return .needsAdministrator }
        return .failure(String(cString: strerror(code)))
    }

    func terminateAsAdministrator(_ item: ProcessItem, force: Bool) async -> TerminationResult {
        if item.pid <= 1 || Self.protectedNames.contains(item.name) { return .protected }
        let signal = force ? 9 : 15
        let pid = item.pid
        let result = await Task.detached { Shell.runAsAdministrator("/bin/kill -\(signal) \(pid)") }.value
        refreshSoon()
        if result.succeeded { return .success }
        if result.wasCancelledByUser { return .failure("Operação cancelada.") }
        return .failure(result.error.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func refreshSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            refresh()
        }
    }
}

/// Process icons are looked up by bundle path and cached, since the list refreshes every few seconds.
@MainActor
final class IconCache {
    static let shared = IconCache()

    private var cache: [String: NSImage] = [:]
    private lazy var executableIcon = NSWorkspace.shared.icon(for: .unixExecutable)

    func icon(forProcess item: ProcessItem) -> NSImage {
        guard let bundle = item.bundlePath else { return executableIcon }
        return icon(forPath: bundle)
    }

    func icon(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}
