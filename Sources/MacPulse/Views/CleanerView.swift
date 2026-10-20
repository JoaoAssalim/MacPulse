import SwiftUI

struct CleanerView: View {
    @Environment(CleanerStore.self) private var cleaner
    @Environment(DiskStore.self) private var disks

    @State private var confirmClean = false
    @State private var confirmMaintenance: MaintenanceAction?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary

                if cleaner.needsFullDiskAccess { fullDiskAccessBanner }
                if let report = cleaner.lastReport { reportBanner(report) }

                VStack(spacing: 0) {
                    ForEach(cleaner.categories) { category in
                        CategoryRow(category: category)
                        if category.id != cleaner.categories.last?.id { Divider() }
                    }
                }
                .cardBackground()

                maintenance
            }
            .padding(20)
        }
        .navigationTitle("Limpeza")
        .confirmationDialog(
            "Limpar \(Fmt.bytes(cleaner.totalSelected))?",
            isPresented: $confirmClean
        ) {
            Button("Limpar \(cleaner.selectedCount) itens", role: .destructive) {
                Task {
                    await cleaner.clean()
                    disks.refreshVolumes()
                }
            }
        } message: {
            Text("Caches, logs e itens da Lixeira são excluídos permanentemente. Downloads e backups vão para o Lixo.")
        }
        .confirmationDialog(
            confirmMaintenance?.title ?? "",
            isPresented: Binding(get: { confirmMaintenance != nil }, set: { if !$0 { confirmMaintenance = nil } }),
            presenting: confirmMaintenance
        ) { action in
            Button("Executar") {
                Task {
                    await cleaner.run(action)
                    disks.refreshVolumes()
                }
            }
        } message: { action in
            Text(action.detail + (action.requiresAdministrator ? "\n\nO macOS vai pedir sua senha de administrador." : ""))
        }
        .alert(
            cleaner.maintenanceReport?.action.title ?? "",
            isPresented: Binding(
                get: { cleaner.maintenanceReport != nil },
                set: { if !$0 { cleaner.maintenanceReport = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cleaner.maintenanceReport?.message ?? "")
        }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: cleaner.isScanning || cleaner.isCleaning)
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                if cleaner.isScanning {
                    Text("Analisando…").font(.title2.weight(.semibold))
                    Text(cleaner.scanningTitle ?? "").foregroundStyle(.secondary)
                } else if cleaner.isCleaning {
                    Text("Limpando…").font(.title2.weight(.semibold))
                    Text("Removendo \(cleaner.selectedCount) itens").foregroundStyle(.secondary)
                } else if cleaner.hasScanned {
                    Text("\(Fmt.bytes(cleaner.totalSelected)) selecionados")
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(Fmt.bytes(cleaner.totalFound)) encontrados no total · \(cleaner.selectedCount) itens marcados")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Libere espaço no seu Mac").font(.title2.weight(.semibold))
                    Text("Procura caches, logs, Lixeira, sobras do Xcode e pacotes de desenvolvimento.")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if cleaner.isScanning || cleaner.isCleaning {
                ProgressView().controlSize(.large)
            } else {
                Button {
                    Task { await cleaner.scan() }
                } label: {
                    Label(cleaner.hasScanned ? "Analisar de novo" : "Analisar", systemImage: "magnifyingglass")
                        .padding(.horizontal, 6)
                }
                .controlSize(.large)

                if cleaner.hasScanned {
                    Button {
                        confirmClean = true
                    } label: {
                        Label("Limpar", systemImage: "trash")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(cleaner.selectedCount == 0)
                }
            }
        }
        .padding(18)
        .cardBackground()
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Algumas pastas precisam de Acesso Total ao Disco").font(.callout.weight(.semibold))
                Text("Ative o MacPulse em Ajustes do Sistema › Privacidade e Segurança › Acesso Total ao Disco e analise de novo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Abrir Ajustes") { Finder.openFullDiskAccessSettings() }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1)))
    }

    private func reportBanner(_ report: CleanReport) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: report.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(report.failures.isEmpty ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Fmt.bytes(report.freed)) liberados · \(report.removedCount) itens removidos")
                    .font(.callout.weight(.semibold))
                if !report.failures.isEmpty {
                    DisclosureGroup("\(report.failures.count) itens não puderam ser removidos (em uso ou protegidos)") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(report.failures.prefix(30), id: \.self) { Text($0) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }
                    .font(.caption)
                }
            }
            Spacer()
            Button {
                cleaner.lastReport = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill((report.failures.isEmpty ? Color.green : Color.orange).opacity(0.1)))
    }

    // MARK: Maintenance

    private var maintenance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Manutenção").font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                ForEach(MaintenanceAction.allCases) { action in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: action.icon)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(action.title).font(.callout.weight(.semibold))
                                if action.requiresAdministrator {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .help("Requer senha de administrador")
                                }
                            }
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if cleaner.runningMaintenance == action {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Executar") { confirmMaintenance = action }
                                .disabled(cleaner.runningMaintenance != nil)
                        }
                    }
                    .padding(14)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .cardBackground(cornerRadius: 12)
                }
            }
        }
    }
}

private struct CategoryRow: View {
    @Environment(CleanerStore.self) private var cleaner
    let category: CleanCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Checkbox(state: category.selectionState) {
                    cleaner.setSelection(category.selectionState != .all, forCategory: category.id)
                }
                .disabled(category.items.isEmpty || cleaner.isBusy)

                Image(systemName: category.target.icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(category.target.title).font(.body.weight(.medium))
                        if category.target.mode == .trash {
                            Text("vai para o Lixo")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.blue.opacity(0.12)))
                                .foregroundStyle(.blue)
                        }
                    }
                    Text(category.target.detail).font(.caption).foregroundStyle(.secondary)
                    if let warning = category.target.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if category.needsFullDiskAccess {
                        Label("Sem permissão para ler — requer Acesso Total ao Disco", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if cleaner.hasScanned, category.items.isEmpty {
                    Text(category.needsFullDiskAccess ? "Sem acesso" : "Nada encontrado")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else if cleaner.hasScanned {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.bytes(category.totalSize))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                        if category.selectedSize != category.totalSize, category.selectedSize > 0 {
                            Text("\(Fmt.bytes(category.selectedSize)) marcados")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(category.items.count) itens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { cleaner.toggleExpanded(category.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(category.isExpanded ? 90 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(category.items.isEmpty)
                .opacity(category.items.isEmpty ? 0.3 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if category.isExpanded, !category.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(category.items.prefix(200)) { item in
                        HStack(spacing: 10) {
                            Checkbox(state: item.isSelected ? .all : .none) {
                                cleaner.toggleItem(item.id, inCategory: category.id)
                            }
                            .disabled(cleaner.isBusy)
                            FileIcon(path: item.url.path, size: 16)
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Text(item.location)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            Text(Fmt.bytes(item.size))
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button {
                                Finder.reveal(item.url)
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("Mostrar no Finder")
                        }
                        .padding(.vertical, 5)
                        .padding(.leading, 54)
                        .padding(.trailing, 16)
                    }
                    if category.items.count > 200 {
                        Text("+ \(category.items.count - 200) itens menores")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.bottom, 8)
                .background(Color.primary.opacity(0.025))
            }
        }
    }
}
