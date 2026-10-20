import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            List(selection: $appState.selection) {
                Section("MacPulse") {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.title, systemImage: item.icon)
                            .tag(item)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                SidebarStats()
                    .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            switch appState.selection ?? .overview {
            case .overview: DashboardView()
            case .disks: DiskView()
            case .cleaner: CleanerView()
            case .processes: ProcessesView()
            }
        }
        #if DEBUG
        .task { await DebugSnapshots.run(appState: appState, cleaner: cleaner, disks: disks) }
        #endif
    }

    #if DEBUG
    @Environment(CleanerStore.self) private var cleaner
    @Environment(DiskStore.self) private var disks
    #endif
}

private struct SidebarStats: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(DiskStore.self) private var disks

    var body: some View {
        VStack(spacing: 10) {
            MiniStat(title: "CPU", fraction: monitor.cpuUsage, detail: Fmt.percent(monitor.cpuUsage))
            MiniStat(
                title: "Memória",
                fraction: monitor.memory.usedFraction,
                detail: "\(Fmt.memory(monitor.memory.used)) / \(Fmt.memory(monitor.memory.total))"
            )
            if let volume = disks.startupVolume {
                MiniStat(title: "Disco", fraction: volume.usedFraction, detail: "\(Fmt.bytes(volume.available)) livres")
            }
        }
        .padding(12)
        .cardBackground(cornerRadius: 10)
    }
}

struct MenuBarView: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(DiskStore.self) private var disks
    @Environment(ProcessStore.self) private var processes
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacPulse").font(.headline)

            MiniStat(title: "CPU", fraction: monitor.cpuUsage, detail: Fmt.percent(monitor.cpuUsage))
            MiniStat(
                title: "Memória",
                fraction: monitor.memory.usedFraction,
                detail: "\(Fmt.memory(monitor.memory.used)) · pressão \(monitor.memory.pressure.label.lowercased())"
            )
            if let volume = disks.startupVolume {
                MiniStat(title: volume.name, fraction: volume.usedFraction, detail: "\(Fmt.bytes(volume.available)) livres")
            }

            Divider()

            Text("Maior uso de CPU").font(.caption).foregroundStyle(.secondary)
            ForEach(processes.topByCPU.prefix(3)) { item in
                HStack {
                    Image(nsImage: IconCache.shared.icon(forProcess: item))
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%%", item.cpu)).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Divider()

            HStack {
                Button("Abrir MacPulse") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}
