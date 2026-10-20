#if DEBUG
import AppKit
import SwiftUI

/// Development aid: `MACPULSE_SNAPSHOT_DIR=/some/dir swift run` walks through every tab
/// and saves a PNG of the main window for each, then quits.
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["MACPULSE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func run(appState: AppState, cleaner: CleanerStore, disks: DiskStore) async {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        disks.analyze(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"))
        await cleaner.scan()

        for item in SidebarItem.allCases {
            appState.selection = item
            try? await Task.sleep(for: .seconds(3))
            save(to: directory.appendingPathComponent("\(item.rawValue).png"))
        }
        NSApp.terminate(nil)
    }

    private static func save(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
