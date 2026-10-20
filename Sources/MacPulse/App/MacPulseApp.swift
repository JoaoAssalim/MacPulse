import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) instead of a .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the menu bar monitor alive after the main window is closed.
        false
    }
}

@main
struct MacPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var appState = AppState()
    @State private var monitor = SystemMonitor()
    @State private var processes = ProcessStore()
    @State private var disks = DiskStore()
    @State private var cleaner = CleanerStore()

    var body: some Scene {
        Window("MacPulse", id: "main") {
            ContentView()
                .environment(appState)
                .environment(monitor)
                .environment(processes)
                .environment(disks)
                .environment(cleaner)
                .frame(minWidth: 1000, minHeight: 660)
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Navegar") {
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { appState.selection = item }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(monitor)
                .environment(disks)
                .environment(processes)
        } label: {
            Image(systemName: "gauge.with.dots.needle.50percent")
        }
        .menuBarExtraStyle(.window)
    }
}
