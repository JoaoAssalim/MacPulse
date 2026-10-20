import Darwin
import Foundation
import Observation

struct UsageSample: Identifiable {
    let id: Int
    let value: Double
}

@MainActor
@Observable
final class SystemMonitor {
    private(set) var cpuUsage: Double = 0
    private(set) var cpuUser: Double = 0
    private(set) var cpuSystem: Double = 0
    private(set) var cpuHistory: [UsageSample] = []
    private(set) var memory = MemorySnapshot()
    private(set) var memoryHistory: [UsageSample] = []
    private(set) var loadAverage: [Double] = [0, 0, 0]
    private(set) var uptime: TimeInterval = 0
    let hardware = HardwareInfo.current

    @ObservationIgnored private var previousTicks: CPUTicks?
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var timer: Timer?
    private let historyLength = 80

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        if let ticks = CPUTicks.read() {
            if let previous = previousTicks {
                let user = Double(ticks.user &- previous.user) + Double(ticks.nice &- previous.nice)
                let system = Double(ticks.system &- previous.system)
                let idle = Double(ticks.idle &- previous.idle)
                let total = user + system + idle
                if total > 0 {
                    cpuUser = user / total
                    cpuSystem = system / total
                    cpuUsage = (user + system) / total
                }
            }
            previousTicks = ticks
        }

        memory = MemorySnapshot.read()

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { loadAverage = loads }
        uptime = ProcessInfo.processInfo.systemUptime

        tick += 1
        append(cpuUsage, to: &cpuHistory)
        append(memory.usedFraction, to: &memoryHistory)
    }

    private func append(_ value: Double, to history: inout [UsageSample]) {
        history.append(UsageSample(id: tick, value: value))
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
    }
}
