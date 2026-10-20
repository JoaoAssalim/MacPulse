import SwiftUI

struct DashboardView: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(ProcessStore.self) private var processes
    @Environment(DiskStore.self) private var disks
    @Environment(CleanerStore.self) private var cleaner
    @Environment(AppState.self) private var appState

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                LazyVGrid(columns: columns, spacing: 16) {
                    cpuCard.frame(height: 270)
                    memoryCard.frame(height: 270)
                    diskCard.frame(height: 270)
                    topCPUCard.frame(height: 250)
                    topMemoryCard.frame(height: 250)
                    systemCard.frame(height: 250)
                }

                quickActions
            }
            .padding(20)
        }
        .navigationTitle("Visão Geral")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(monitor.hardware.hostName).font(.title2.weight(.semibold))
                Text("\(monitor.hardware.chip) · \(monitor.hardware.osVersion) · ligado há \(Fmt.duration(monitor.uptime))")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            healthBadge
        }
    }

    private var healthBadge: some View {
        let issues = healthIssues
        return Label(
            issues.isEmpty ? "Sistema saudável" : issues.joined(separator: " · "),
            systemImage: issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
        )
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill((issues.isEmpty ? Color.green : Color.orange).opacity(0.15)))
        .foregroundStyle(issues.isEmpty ? Color.green : Color.orange)
    }

    private var healthIssues: [String] {
        var issues: [String] = []
        if monitor.cpuUsage > 0.85 { issues.append("CPU alta") }
        if monitor.memory.pressure != .normal { issues.append("Pressão de memória \(monitor.memory.pressure.label.lowercased())") }
        if let volume = disks.startupVolume, volume.usedFraction > 0.9 { issues.append("Disco quase cheio") }
        return issues
    }

    // MARK: Cards

    private var cpuCard: some View {
        Card("Processador", systemImage: "cpu") {
            HStack(spacing: 18) {
                RingGauge(value: monitor.cpuUsage, caption: "em uso")
                    .frame(width: 104, height: 104)
                VStack(spacing: 6) {
                    MetricRow(label: "Usuário", value: Fmt.percent(monitor.cpuUser), color: .blue)
                    MetricRow(label: "Sistema", value: Fmt.percent(monitor.cpuSystem), color: .red)
                    MetricRow(label: "Ociosa", value: Fmt.percent(max(0, 1 - monitor.cpuUsage)))
                    MetricRow(label: "Núcleos", value: "\(monitor.hardware.cores)")
                    MetricRow(
                        label: "Carga média",
                        value: monitor.loadAverage.map { String(format: "%.1f", $0) }.joined(separator: " · ")
                    )
                }
            }
            UsageChart(samples: monitor.cpuHistory, color: .blue)
        }
    }

    private var memoryCard: some View {
        let memory = monitor.memory
        return Card("Memória", systemImage: "memorychip") {
            HStack(spacing: 18) {
                RingGauge(value: memory.usedFraction, caption: Fmt.memory(memory.used))
                    .frame(width: 104, height: 104)
                VStack(spacing: 6) {
                    MetricRow(label: "Apps", value: Fmt.memory(memory.app), color: .yellow)
                    MetricRow(label: "Fixa", value: Fmt.memory(memory.wired), color: .orange)
                    MetricRow(label: "Comprimida", value: Fmt.memory(memory.compressed), color: .purple)
                    MetricRow(label: "Em cache", value: Fmt.memory(memory.cached))
                    MetricRow(label: "Swap", value: Fmt.memory(memory.swapUsed))
                }
            }
            UsageChart(samples: monitor.memoryHistory, color: .purple)
        }
    }

    private var diskCard: some View {
        Card("Disco de inicialização", systemImage: "internaldrive") {
            if let volume = disks.startupVolume {
                HStack(spacing: 18) {
                    RingGauge(value: volume.usedFraction, caption: "ocupado")
                        .frame(width: 104, height: 104)
                    VStack(spacing: 6) {
                        MetricRow(label: "Volume", value: volume.name)
                        MetricRow(label: "Capacidade", value: Fmt.bytes(volume.total))
                        MetricRow(label: "Usado", value: Fmt.bytes(volume.used), color: .usage(volume.usedFraction))
                        MetricRow(label: "Disponível", value: Fmt.bytes(volume.available), color: .secondary)
                        MetricRow(label: "Purgeável", value: Fmt.bytes(volume.purgeable))
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    if cleaner.hasScanned {
                        Text("\(Fmt.bytes(cleaner.totalFound)) de lixo encontrado")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        appState.selection = .cleaner
                        if !cleaner.hasScanned { Task { await cleaner.scan() } }
                    } label: {
                        Label("Limpar disco", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView("Nenhum volume", systemImage: "internaldrive")
            }
        }
    }

    private var topCPUCard: some View {
        Card("Maior uso de CPU", systemImage: "flame") {
            processList(processes.topByCPU) { item in
                (String(format: "%.1f%%", item.cpu), min(item.cpu / 100, 1))
            }
        }
    }

    private var topMemoryCard: some View {
        let total = Double(monitor.memory.total)
        return Card("Maior uso de memória", systemImage: "square.stack.3d.up") {
            processList(processes.topByMemory) { item in
                (Fmt.memory(item.memoryBytes), total > 0 ? Double(item.memoryBytes) / total : 0)
            }
        }
    }

    private func processList(
        _ items: [ProcessItem],
        metric: @escaping (ProcessItem) -> (String, Double)
    ) -> some View {
        VStack(spacing: 9) {
            ForEach(items) { item in
                let (text, fraction) = metric(item)
                HStack(spacing: 8) {
                    Image(nsImage: IconCache.shared.icon(forProcess: item))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    UsageBar(fraction: fraction, tint: .accentColor, height: 5)
                        .frame(width: 60)
                    Text(text)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.callout)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Ver todos os processos") { appState.selection = .processes }
                    .buttonStyle(.link)
            }
        }
    }

    private var systemCard: some View {
        let hardware = monitor.hardware
        return Card("Este Mac", systemImage: "laptopcomputer") {
            VStack(spacing: 8) {
                MetricRow(label: "Chip", value: hardware.chip)
                MetricRow(label: "Modelo", value: hardware.model)
                MetricRow(label: "Memória física", value: Fmt.memory(hardware.memory))
                MetricRow(label: "Sistema", value: hardware.osVersion)
                MetricRow(label: "Tempo ligado", value: Fmt.duration(monitor.uptime))
                MetricRow(label: "Processos ativos", value: "\(processes.processes.count)")
                MetricRow(label: "Pressão de memória", value: monitor.memory.pressure.label)
            }
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickAction("Procurar lixo", systemImage: "sparkles", detail: "Caches, logs, Lixeira e mais") {
                appState.selection = .cleaner
                Task { await cleaner.scan() }
            }
            quickAction("Liberar memória", systemImage: "memorychip", detail: "Descarta memória inativa") {
                Task { await cleaner.run(.purgeMemory) }
            }
            quickAction("Analisar disco", systemImage: "chart.bar.doc.horizontal", detail: "Veja o que ocupa espaço") {
                appState.selection = .disks
                if disks.analyzerEntries.isEmpty { disks.analyze(disks.analyzerRoot) }
            }
            quickAction("Processos", systemImage: "list.bullet.rectangle", detail: "Encerre o que está travando") {
                appState.selection = .processes
            }
        }
    }

    private func quickAction(
        _ title: String,
        systemImage: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .cardBackground(cornerRadius: 10)
        }
        .buttonStyle(.plain)
    }
}
