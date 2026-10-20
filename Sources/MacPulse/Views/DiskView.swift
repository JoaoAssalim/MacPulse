import SwiftUI

struct DiskView: View {
    @Environment(DiskStore.self) private var disks

    @State private var tab: Tab = .analyzer
    @State private var pendingTrash: URL?
    @State private var errorMessage: String?

    enum Tab: String, CaseIterable, Identifiable {
        case analyzer = "Analisador de espaço"
        case largeFiles = "Arquivos grandes"
        var id: String { rawValue }
    }

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(disks.volumes) { volume in
                    VolumeCard(volume: volume) {
                        do { try disks.eject(volume) } catch { errorMessage = error.localizedDescription }
                    }
                }
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)

            switch tab {
            case .analyzer: SpaceAnalyzerView(onTrash: { pendingTrash = $0 })
            case .largeFiles: LargeFilesView(onTrash: { pendingTrash = $0 })
            }
        }
        .padding(20)
        .navigationTitle("Discos")
        .toolbar {
            Button {
                disks.refreshVolumes()
            } label: {
                Label("Atualizar volumes", systemImage: "arrow.clockwise")
            }
        }
        .confirmationDialog(
            "Mover para o Lixo?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { url in
            Button("Mover \"\(url.lastPathComponent)\" para o Lixo", role: .destructive) {
                do { try disks.moveToTrash(url) } catch { errorMessage = error.localizedDescription }
            }
        } message: { url in
            Text("\(url.path.abbreviatingHome)\n\nVocê poderá recuperá-lo pela Lixeira até esvaziá-la.")
        }
        .alert(
            "Não foi possível concluir",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct VolumeCard: View {
    let volume: VolumeInfo
    let onEject: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(volume.name).font(.headline)
                    Text(volume.format).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Finder.reveal(volume.url)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Abrir no Finder")
                    if volume.isEjectable {
                        Button(action: onEject) { Image(systemName: "eject") }
                            .buttonStyle(.borderless)
                            .help("Ejetar")
                    }
                }

                UsageBar(fraction: volume.usedFraction, height: 10)

                HStack {
                    Text("\(Fmt.bytes(volume.used)) usados de \(Fmt.bytes(volume.total))")
                    Spacer()
                    Text("\(Fmt.bytes(volume.available)) disponíveis")
                        .fontWeight(.medium)
                }
                .font(.caption)
                .monospacedDigit()

                if volume.purgeable > 100_000_000 {
                    Text("Inclui \(Fmt.bytes(volume.purgeable)) purgeáveis (snapshots e caches que o macOS libera sob demanda)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .cardBackground()
    }
}

// MARK: - Space analyzer

private struct SpaceAnalyzerView: View {
    @Environment(DiskStore.self) private var disks
    let onTrash: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    disks.goUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(!disks.canGoUp)
                .help("Pasta acima")

                FileIcon(path: disks.analyzerRoot.path)
                Text(disks.analyzerRoot.path.abbreviatingHome)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !disks.analyzerEntries.isEmpty {
                    Text(Fmt.bytes(disks.analyzerTotalSize))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                if disks.isAnalyzing {
                    ProgressView(value: Double(disks.analyzerCompleted), total: Double(max(disks.analyzerTotal, 1)))
                        .frame(width: 120)
                    Text("\(disks.analyzerCompleted)/\(disks.analyzerTotal)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Parar") { disks.cancelAnalysis() }
                }

                Button("Escolher pasta…") {
                    if let url = Finder.chooseFolder(prompt: "Analisar", startingAt: disks.analyzerRoot) {
                        disks.analyze(url)
                    }
                }
                Button {
                    disks.analyze(disks.analyzerRoot)
                } label: {
                    Label("Analisar", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(disks.isAnalyzing)
            }

            if disks.analyzerEntries.isEmpty, !disks.isAnalyzing {
                ContentUnavailableView {
                    Label("Descubra o que ocupa espaço", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("Calcula o tamanho de cada item da pasta. Dê dois cliques numa pasta para entrar nela.")
                } actions: {
                    Button("Analisar pasta pessoal") {
                        disks.analyze(FileManager.default.homeDirectoryForCurrentUser)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let largest = disks.analyzerEntries.first?.size ?? 1
                let total = max(disks.analyzerTotalSize, 1)
                List(disks.analyzerEntries) { entry in
                    HStack(spacing: 10) {
                        FileIcon(path: entry.url.path, size: 20)
                        Text(entry.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(minWidth: 160, alignment: .leading)
                        UsageBar(fraction: Double(entry.size) / Double(max(largest, 1)), tint: .accentColor, height: 8)
                        Text(Fmt.percent(Double(entry.size) / Double(total)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                        Text(Fmt.bytes(entry.size))
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .opacity(entry.isDirectory ? 1 : 0)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if entry.isDirectory { disks.analyze(entry.url) }
                    }
                    .contextMenu {
                        if entry.isDirectory {
                            Button("Abrir no analisador") { disks.analyze(entry.url) }
                        }
                        Button("Mostrar no Finder") { Finder.reveal(entry.url) }
                        Divider()
                        Button("Mover para o Lixo…", role: .destructive) { onTrash(entry.url) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

// MARK: - Large files

private struct LargeFilesView: View {
    @Environment(DiskStore.self) private var disks
    let onTrash: (URL) -> Void

    @State private var selection: FileEntry.ID?
    @State private var sortOrder = [KeyPathComparator(\FileEntry.size, order: .reverse)]

    private let thresholds: [(String, Int64)] = [
        ("100 MB", 100_000_000), ("500 MB", 500_000_000), ("1 GB", 1_000_000_000), ("5 GB", 5_000_000_000),
    ]

    var body: some View {
        @Bindable var disks = disks
        let files = disks.largeFiles.sorted(using: sortOrder)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Maiores que", selection: $disks.largeFileThreshold) {
                    ForEach(thresholds, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 190)

                Text("em").foregroundStyle(.secondary)
                Button(disks.largeFilesRoot.path.abbreviatingHome) {
                    if let url = Finder.chooseFolder(prompt: "Escolher", startingAt: disks.largeFilesRoot) {
                        disks.largeFilesRoot = url
                    }
                }

                Spacer()

                if disks.isScanningLargeFiles {
                    ProgressView().controlSize(.small)
                    Text("\(disks.largeFilesScanned.formatted()) arquivos verificados")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Parar") { disks.cancelLargeFiles() }
                } else {
                    Button {
                        disks.scanLargeFiles()
                    } label: {
                        Label("Procurar", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if files.isEmpty, !disks.isScanningLargeFiles {
                ContentUnavailableView {
                    Label(
                        disks.hasScannedLargeFiles ? "Nenhum arquivo grande encontrado" : "Encontre arquivos grandes",
                        systemImage: "doc.badge.ellipsis"
                    )
                } description: {
                    Text("Vídeos, imagens de disco e instaladores esquecidos costumam ser os maiores vilões.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(files, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Nome", value: \.name) { file in
                        HStack(spacing: 8) {
                            FileIcon(path: file.url.path)
                            Text(file.name).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .width(min: 200, ideal: 280)
                    TableColumn("Local", value: \.folder) { file in
                        Text(file.folder).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                    TableColumn("Tamanho", value: \.size) { file in
                        Text(Fmt.bytes(file.size)).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Modificado", value: \.modified) { file in
                        Text(file.modified, format: .dateTime.day().month().year())
                            .foregroundStyle(.secondary)
                    }
                    .width(110)
                }
                .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
                    if let url = ids.first {
                        Button("Mostrar no Finder") { Finder.reveal(url) }
                        Divider()
                        Button("Mover para o Lixo…", role: .destructive) { onTrash(url) }
                    }
                } primaryAction: { ids in
                    if let url = ids.first { Finder.reveal(url) }
                }

                HStack {
                    Text("\(files.count) arquivos · \(Fmt.bytes(files.reduce(0) { $0 + $1.size })) no total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Mostrar no Finder") { if let selection { Finder.reveal(selection) } }
                        .disabled(selection == nil)
                    Button("Mover para o Lixo…", role: .destructive) { if let selection { onTrash(selection) } }
                        .disabled(selection == nil)
                }
            }
        }
    }
}
