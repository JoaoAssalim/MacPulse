import AppKit
import SwiftUI

/// Masks personal details (computer name, user name) while capturing documentation screenshots.
enum DemoMode {
    #if DEBUG
    static let isEnabled = ProcessInfo.processInfo.environment["MACPULSE_SNAPSHOT_DIR"] != nil
    #else
    static let isEnabled = false
    #endif

    static let hostName = "MacBook Pro"
    static let userName = "you"
}

#if DEBUG
/// Development aid: `MACPULSE_SNAPSHOT_DIR=/some/dir swift run` walks through every tab
/// and saves a 2x PNG of the main window for each, then quits.
@MainActor
enum DebugSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["MACPULSE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func run(appState: AppState, cleaner: CleanerStore, disks: DiskStore) async {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        mainWindow?.setContentSize(NSSize(width: 1280, height: 820))
        mainWindow?.center()

        disks.analyze(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library"))
        await cleaner.scan()

        for item in SidebarItem.allCases {
            appState.selection = item
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(4))
            save(to: directory.appendingPathComponent("\(item.rawValue).png"))
        }
        NSApp.terminate(nil)
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.frame.width > 600 }
    }

    private static func save(to url: URL) {
        guard let window = mainWindow,
              let view = window.contentView?.superview ?? window.contentView else { return }
        let scale: CGFloat = 2
        let bounds = view.bounds
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
