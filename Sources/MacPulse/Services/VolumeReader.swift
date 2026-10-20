import Foundation

struct VolumeInfo: Identifiable {
    let url: URL
    let name: String
    let format: String
    let total: Int64
    /// Truly free bytes right now.
    let free: Int64
    /// Free bytes including purgeable space macOS can reclaim on demand (what Finder shows).
    let availableForImportantUsage: Int64
    let isInternal: Bool
    let isEjectable: Bool
    let isRoot: Bool

    var id: URL { url }
    var available: Int64 { max(availableForImportantUsage, free) }
    var used: Int64 { max(total - available, 0) }
    var purgeable: Int64 { max(availableForImportantUsage - free, 0) }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

enum VolumeReader {
    private static let keys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeLocalizedFormatDescriptionKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey,
        .volumeIsEjectableKey,
        .volumeIsRootFileSystemKey,
    ]

    static func volumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity, total > 0 else { return nil }
            let free = Int64(values.volumeAvailableCapacity ?? 0)
            return VolumeInfo(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                format: values.volumeLocalizedFormatDescription ?? "",
                total: Int64(total),
                free: free,
                availableForImportantUsage: values.volumeAvailableCapacityForImportantUsage ?? free,
                isInternal: values.volumeIsInternal ?? false,
                isEjectable: values.volumeIsEjectable ?? false,
                isRoot: values.volumeIsRootFileSystem ?? (url.path == "/")
            )
        }
        .sorted { lhs, rhs in
            if lhs.isRoot != rhs.isRoot { return lhs.isRoot }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
