import AppKit
import Observation

@MainActor
@Observable
final class DiskStore {
    private(set) var volumes: [VolumeInfo] = []

    private(set) var analyzerRoot = FileManager.default.homeDirectoryForCurrentUser
    private(set) var analyzerEntries: [FolderEntry] = []
    private(set) var analyzerCompleted = 0
    private(set) var analyzerTotal = 0
    private(set) var isAnalyzing = false

    private(set) var largeFiles: [FileEntry] = []
    private(set) var largeFilesScanned = 0
    private(set) var isScanningLargeFiles = false
    private(set) var hasScannedLargeFiles = false
    var largeFilesRoot = FileManager.default.homeDirectoryForCurrentUser
    var largeFileThreshold: Int64 = 500_000_000

    @ObservationIgnored private var analyzeTask: Task<Void, Never>?
    @ObservationIgnored private var largeFilesTask: Task<Void, Never>?
    @ObservationIgnored private var largeFilesScanID = UUID()
    @ObservationIgnored private var timer: Timer?

    init() {
        refreshVolumes()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVolumes() }
        }
    }

    var startupVolume: VolumeInfo? { volumes.first(where: \.isRoot) ?? volumes.first }
    var analyzerTotalSize: Int64 { analyzerEntries.reduce(0) { $0 + $1.size } }
    var canGoUp: Bool { analyzerRoot.path != "/" }

    func refreshVolumes() {
        volumes = VolumeReader.volumes()
    }

    func eject(_ volume: VolumeInfo) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
        refreshVolumes()
    }

    // MARK: Space analyzer

    func analyze(_ root: URL) {
        analyzeTask?.cancel()
        analyzerRoot = root
        analyzerEntries = []
        analyzerCompleted = 0

        let children = ((try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []).filter { !FileScanner.skippedPaths.contains($0.path) }

        analyzerTotal = children.count
        isAnalyzing = true

        analyzeTask = Task { [weak self] in
            await withTaskGroup(of: FolderEntry.self) { group in
                for child in children {
                    group.addTask {
                        let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        return FolderEntry(url: child, size: FileScanner.allocatedSize(of: child), isDirectory: isDirectory == true)
                    }
                }
                for await entry in group {
                    guard let self, !Task.isCancelled else { return }
                    self.analyzerCompleted += 1
                    guard entry.size > 0 else { continue }
                    let index = self.analyzerEntries.firstIndex { $0.size < entry.size } ?? self.analyzerEntries.endIndex
                    self.analyzerEntries.insert(entry, at: index)
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.isAnalyzing = false
        }
    }

    func cancelAnalysis() {
        analyzeTask?.cancel()
        isAnalyzing = false
    }

    func goUp() {
        guard canGoUp else { return }
        analyze(analyzerRoot.deletingLastPathComponent())
    }

    // MARK: Large files

    func scanLargeFiles() {
        largeFilesTask?.cancel()
        let scanID = UUID()
        largeFilesScanID = scanID
        largeFiles = []
        largeFilesScanned = 0
        isScanningLargeFiles = true

        let root = largeFilesRoot
        let threshold = largeFileThreshold
        largeFilesTask = Task.detached(priority: .userInitiated) { [weak self] in
            let files = FileScanner.largeFiles(in: root, minimumSize: threshold, limit: 400) { [weak self] count in
                Task { @MainActor [weak self] in
                    self?.updateLargeFilesProgress(count, scanID: scanID)
                }
            }
            let cancelled = Task.isCancelled
            await self?.finishLargeFilesScan(cancelled ? nil : files, scanID: scanID)
        }
    }

    private func updateLargeFilesProgress(_ count: Int, scanID: UUID) {
        guard largeFilesScanID == scanID else { return }
        largeFilesScanned = count
    }

    private func finishLargeFilesScan(_ files: [FileEntry]?, scanID: UUID) {
        guard largeFilesScanID == scanID else { return }
        if let files { largeFiles = files }
        isScanningLargeFiles = false
        hasScannedLargeFiles = true
    }

    func cancelLargeFiles() {
        largeFilesTask?.cancel()
        largeFilesScanID = UUID()
        isScanningLargeFiles = false
    }

    // MARK: Actions

    func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        analyzerEntries.removeAll { $0.url == url }
        largeFiles.removeAll { $0.url == url }
        refreshVolumes()
    }
}
