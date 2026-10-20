import Darwin
import Foundation

private let hostPort = mach_host_self()

struct CPUTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    static func read() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }
}

enum MemoryPressure: Int {
    case normal = 1
    case warning = 2
    case critical = 4

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Alerta"
        case .critical: "Crítica"
        }
    }
}

struct MemorySnapshot {
    var total: UInt64 = ProcessInfo.processInfo.physicalMemory
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var pressure: MemoryPressure = .normal

    /// Same definition Activity Monitor uses for "Memory Used".
    var used: UInt64 { app + wired + compressed }
    var available: UInt64 { total > used ? total - used : 0 }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }

    static func read() -> MemorySnapshot {
        var snapshot = MemorySnapshot()

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            snapshot.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            snapshot.wired = UInt64(stats.wire_count) * page
            snapshot.compressed = UInt64(stats.compressor_page_count) * page
            snapshot.cached = (UInt64(stats.external_page_count) + purgeable) * page
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            snapshot.swapUsed = swap.xsu_used
        }

        if let level = Sysctl.int32("kern.memorystatus_vm_pressure_level"),
           let pressure = MemoryPressure(rawValue: Int(level)) {
            snapshot.pressure = pressure
        }

        return snapshot
    }
}

struct HardwareInfo {
    let chip: String
    let model: String
    let cores: Int
    let memory: UInt64
    let osVersion: String
    let hostName: String

    static let current: HardwareInfo = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return HardwareInfo(
            chip: Sysctl.string("machdep.cpu.brand_string") ?? "Apple Silicon",
            model: Sysctl.string("hw.model") ?? "Mac",
            cores: ProcessInfo.processInfo.activeProcessorCount,
            memory: ProcessInfo.processInfo.physicalMemory,
            osVersion: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            hostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        )
    }()
}

enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func int32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
