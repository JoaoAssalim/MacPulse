import Foundation

struct FolderEntry: Identifiable {
    let url: URL
    let size: Int64
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct FileEntry: Identifiable {
    let url: URL
    let size: Int64
    let modified: Date

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path.abbreviatingHome }
}

/// Synchronous, cancellation-aware file system walkers. Call from background tasks.
enum FileScanner {
    /// Paths that would double count the data volume or are not real files.
    static let skippedPaths: Set<String> = [
        "/System/Volumes",
        "/Volumes",
        "/dev",
        "/private/var/vm",
        "/private/var/folders",
    ]

    private static let sizeKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return 0
        }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true { return fileSize(url) }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        var visited = 0
        while let item = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 512 == 0, Task.isCancelled { break }
            if skippedPaths.contains(item.path) {
                enumerator.skipDescendants()
                continue
            }
            guard let fileValues = try? item.resourceValues(forKeys: sizeKeys),
                  fileValues.isRegularFile == true else { continue }
            total += Int64(fileValues.totalFileAllocatedSize ?? fileValues.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: sizeKeys) else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    static func largeFiles(
        in root: URL,
        minimumSize: Int64,
        limit: Int,
        progress: (Int) -> Void
    ) -> [FileEntry] {
        let keys: Set<URLResourceKey> = sizeKeys.union([.contentModificationDateKey])
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [FileEntry] = []
        var visited = 0
        while let item = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 2_000 == 0 {
                if Task.isCancelled { break }
                progress(visited)
            }
            if skippedPaths.contains(item.path) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if size >= minimumSize {
                found.append(FileEntry(url: item, size: size, modified: values.contentModificationDate ?? .distantPast))
            }
        }
        progress(visited)
        return Array(found.sorted { $0.size > $1.size }.prefix(limit))
    }
}

extension String {
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
    var expandingTilde: String { (self as NSString).expandingTildeInPath }
}
