import Foundation

struct ProcessItem: Identifiable, Hashable {
    let pid: Int32
    let ppid: Int32
    let user: String
    let cpu: Double
    let memoryPercent: Double
    let memoryBytes: Int64
    let path: String
    var name: String
    var isApp = false

    var id: Int32 { pid }

    /// Outermost `.app` bundle the executable lives in, if any.
    var bundlePath: String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }

    var isOwnedByCurrentUser: Bool { user == NSUserName() }
}

enum ProcessReader {
    static func snapshot() -> [ProcessItem] {
        let result = Shell.run(
            "/bin/ps",
            ["-axo", "pid=,ppid=,user=,pcpu=,pmem=,rss=,comm="],
            environment: ["LC_ALL": "C"]
        )
        guard result.succeeded else { return [] }
        return result.output.split(separator: "\n").compactMap(parse)
    }

    private static func parse(_ line: Substring) -> ProcessItem? {
        let fields = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
        guard fields.count == 7,
              let pid = Int32(fields[0]),
              let ppid = Int32(fields[1]) else { return nil }

        let path = fields[6].trimmingCharacters(in: .whitespaces)
        let rssKB = Int64(fields[5]) ?? 0
        return ProcessItem(
            pid: pid,
            ppid: ppid,
            user: String(fields[2]),
            cpu: Double(fields[3]) ?? 0,
            memoryPercent: Double(fields[4]) ?? 0,
            memoryBytes: rssKB * 1024,
            path: path,
            name: (path as NSString).lastPathComponent
        )
    }
}
