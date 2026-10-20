import SwiftUI

struct ProcessesView: View {
    @Environment(ProcessStore.self) private var store

    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var selection: ProcessItem.ID?
    @State private var sortOrder = [KeyPathComparator(\ProcessItem.cpu, order: .reverse)]
    @State private var pendingKill: PendingKill?
    @State private var alert: ProcessAlert?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todos"
        case apps = "Apps"
        case mine = "Meus"
        case system = "Sistema"
        var id: String { rawValue }

        func matches(_ item: ProcessItem) -> Bool {
            switch self {
            case .all: true
            case .apps: item.isApp
            case .mine: item.isOwnedByCurrentUser
            case .system: !item.isOwnedByCurrentUser
            }
        }
    }

    struct PendingKill: Identifiable {
        let item: ProcessItem
        let force: Bool
        var id: String { "\(item.pid)-\(force)" }
    }

    struct ProcessAlert: Identifiable {
        let title: String
        let message: String
        var adminRetry: PendingKill?
        var id: String { title + message }
    }

    private var visibleProcesses: [ProcessItem] {
        store.processes
            .filter { filter.matches($0) }
            .filter { item in
                search.isEmpty
                    || item.name.localizedCaseInsensitiveContains(search)
                    || item.path.localizedCaseInsensitiveContains(search)
                    || String(item.pid) == search
            }
            .sorted(using: sortOrder)
    }

    private var selectedItem: ProcessItem? {
        guard let selection else { return nil }
        return store.processes.first { $0.pid == selection }
    }

    var body: some View {
        @Bindable var store = store
        let items = visibleProcesses

        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)

                Spacer()

                summaryChip("Processos", "\(items.count)")
                summaryChip("CPU total", String(format: "%.0f%%", items.reduce(0) { $0 + $1.cpu } / Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))))
                summaryChip("Memória", Fmt.memory(items.reduce(0) { $0 + $1.memoryBytes }))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Table(items, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Processo", value: \.name) { item in
                    HStack(spacing: 8) {
                        Image(nsImage: IconCache.shared.icon(forProcess: item))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(item.name).lineLimit(1)
                    }
                    .help(item.path)
                }
                .width(min: 200, ideal: 280)

                TableColumn("% CPU", value: \.cpu) { item in
                    Text(String(format: "%.1f", item.cpu))
                        .monospacedDigit()
                        .foregroundStyle(item.cpu >= 80 ? .red : item.cpu >= 30 ? .orange : .primary)
                }
                .width(70)

                TableColumn("Memória", value: \.memoryBytes) { item in
                    Text(Fmt.memory(item.memoryBytes)).monospacedDigit()
                }
                .width(90)

                TableColumn("% Mem", value: \.memoryPercent) { item in
                    Text(String(format: "%.1f", item.memoryPercent)).monospacedDigit()
                }
                .width(60)

                TableColumn("PID", value: \.pid) { item in
                    Text(String(item.pid)).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(65)

                TableColumn("Usuário", value: \.user) { item in
                    Text(item.user).foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 100)
            }
            .contextMenu(forSelectionType: ProcessItem.ID.self) { ids in
                if let pid = ids.first, let item = store.processes.first(where: { $0.pid == pid }) {
                    Button("Encerrar") { pendingKill = PendingKill(item: item, force: false) }
                    Button("Forçar encerramento") { pendingKill = PendingKill(item: item, force: true) }
                    Divider()
                    Button("Mostrar no Finder") { Finder.reveal(URL(fileURLWithPath: item.bundlePath ?? item.path)) }
                    Button("Copiar PID") { copy(String(item.pid)) }
                    Button("Copiar caminho") { copy(item.path) }
                }
            }

            detailBar
        }
        .navigationTitle("Processos")
        .searchable(text: $search, placement: .toolbar, prompt: "Nome, caminho ou PID")
        .toolbar {
            Toggle(isOn: $store.isPaused) {
                Label(store.isPaused ? "Retomar" : "Pausar", systemImage: store.isPaused ? "play.fill" : "pause.fill")
            }
            .help(store.isPaused ? "Retomar atualização automática" : "Pausar atualização automática")
            Button {
                store.refresh()
            } label: {
                Label("Atualizar", systemImage: "arrow.clockwise")
            }
        }
        .confirmationDialog(
            pendingKill.map { "\($0.force ? "Forçar encerramento de" : "Encerrar") \"\($0.item.name)\"?" } ?? "",
            isPresented: Binding(get: { pendingKill != nil }, set: { if !$0 { pendingKill = nil } }),
            presenting: pendingKill
        ) { pending in
            Button(pending.force ? "Forçar encerramento" : "Encerrar", role: .destructive) {
                perform(pending)
            }
        } message: { pending in
            Text(
                pending.force
                    ? "O processo será interrompido imediatamente. Dados não salvos serão perdidos."
                    : "O processo receberá um pedido para encerrar normalmente."
            )
        }
        .alert(item: $alert) { alert in
            if let retry = alert.adminRetry {
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .destructive(Text("Encerrar como administrador")) { performAsAdmin(retry) },
                    secondaryButton: .cancel(Text("Cancelar"))
                )
            } else {
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
        }
    }

    // MARK: Subviews

    private func summaryChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
    }

    @ViewBuilder
    private var detailBar: some View {
        Divider()
        HStack(spacing: 12) {
            if let item = selectedItem {
                Image(nsImage: IconCache.shared.icon(forProcess: item))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.name)  ·  PID \(item.pid)  ·  pai \(item.ppid)")
                        .font(.callout.weight(.semibold))
                    Text(item.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Mostrar no Finder") {
                    Finder.reveal(URL(fileURLWithPath: item.bundlePath ?? item.path))
                }
                Button("Encerrar") { pendingKill = PendingKill(item: item, force: false) }
                Button("Forçar encerramento", role: .destructive) { pendingKill = PendingKill(item: item, force: true) }
                    .tint(.red)
            } else {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Selecione um processo para ver detalhes e encerrá-lo. Clique nos cabeçalhos para ordenar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let updated = store.lastUpdated {
                    Text("Atualizado \(updated, format: .dateTime.hour().minute().second())")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 54)
    }

    // MARK: Actions

    private func perform(_ pending: PendingKill) {
        handle(store.terminate(pending.item, force: pending.force), for: pending)
    }

    private func performAsAdmin(_ pending: PendingKill) {
        Task {
            let result = await store.terminateAsAdministrator(pending.item, force: pending.force)
            handle(result, for: nil)
        }
    }

    private func handle(_ result: TerminationResult, for pending: PendingKill?) {
        switch result {
        case .success:
            if selection == pending?.item.pid { selection = nil }
        case .protected:
            alert = ProcessAlert(
                title: "Processo essencial",
                message: "Encerrar esse processo pode travar o Mac ou encerrar sua sessão, por isso o MacPulse não permite."
            )
        case .needsAdministrator:
            alert = ProcessAlert(
                title: "Permissão necessária",
                message: "Esse processo pertence a outro usuário ou ao sistema. Encerrar como administrador?",
                adminRetry: pending
            )
        case .failure(let message):
            alert = ProcessAlert(title: "Não foi possível encerrar", message: message)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
