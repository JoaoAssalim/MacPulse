import Foundation

enum RemovalMode {
    /// Frees space immediately. Used only for regenerable data (caches, logs, build artifacts).
    case delete
    /// Moves to the Trash so the user can still recover it.
    case trash

    var label: String {
        switch self {
        case .delete: "Excluído permanentemente"
        case .trash: "Movido para o Lixo"
        }
    }
}

struct CleanTarget {
    let id: String
    let title: String
    let detail: String
    let icon: String
    /// Folders whose *contents* are offered for cleaning. The folders themselves are kept.
    let paths: [String]
    var mode: RemovalMode = .delete
    var selectedByDefault = true
    var minimumAgeDays: Int? = nil
    var excludedNames: Set<String> = []
    var warning: String? = nil

    static let all: [CleanTarget] = [
        CleanTarget(
            id: "userCaches",
            title: "Caches de aplicativos",
            detail: "Arquivos temporários que os apps recriam quando precisam.",
            icon: "shippingbox",
            paths: ["~/Library/Caches"],
            excludedNames: [
                "com.macpulse.app", "CloudKit", "com.apple.bird", "com.apple.akd",
                "FamilyCircle", "com.apple.containermanagerd", "com.apple.HomeKit",
                "com.apple.homed", "com.apple.ap.adprivacyd", "com.apple.nsurlsessiond",
            ],
            warning: "Feche os apps antes de limpar para evitar que recriem o cache na hora."
        ),
        CleanTarget(
            id: "logs",
            title: "Logs e relatórios de falhas",
            detail: "Registros antigos de apps e relatórios de diagnóstico.",
            icon: "doc.text.magnifyingglass",
            paths: ["~/Library/Logs"]
        ),
        CleanTarget(
            id: "trash",
            title: "Lixeira",
            detail: "Itens que você já enviou para o Lixo.",
            icon: "trash",
            paths: ["~/.Trash"]
        ),
        CleanTarget(
            id: "xcodeDerivedData",
            title: "Xcode · DerivedData",
            detail: "Builds intermediários e índices do Xcode.",
            icon: "hammer",
            paths: ["~/Library/Developer/Xcode/DerivedData"]
        ),
        CleanTarget(
            id: "simulatorCaches",
            title: "Simulador iOS · caches",
            detail: "Caches do CoreSimulator.",
            icon: "iphone",
            paths: ["~/Library/Developer/CoreSimulator/Caches"]
        ),
        CleanTarget(
            id: "devCaches",
            title: "Caches de desenvolvimento",
            detail: "npm, Yarn, pnpm, Gradle, Cargo e pip.",
            icon: "chevron.left.forwardslash.chevron.right",
            paths: [
                "~/.npm/_cacache",
                "~/.yarn/berry/cache",
                "~/Library/pnpm/store",
                "~/.gradle/caches",
                "~/.cargo/registry/cache",
                "~/.cache/pip",
            ]
        ),
        CleanTarget(
            id: "deviceSupport",
            title: "Xcode · Device Support",
            detail: "Símbolos de iPhones/relógios já conectados ao Xcode.",
            icon: "cable.connector",
            paths: [
                "~/Library/Developer/Xcode/iOS DeviceSupport",
                "~/Library/Developer/Xcode/watchOS DeviceSupport",
            ],
            selectedByDefault: false,
            warning: "São baixados de novo ao reconectar o dispositivo, o que pode demorar."
        ),
        CleanTarget(
            id: "oldDownloads",
            title: "Downloads antigos",
            detail: "Itens da pasta Downloads com mais de 90 dias.",
            icon: "arrow.down.circle",
            paths: ["~/Downloads"],
            mode: .trash,
            selectedByDefault: false,
            minimumAgeDays: 90,
            warning: "Revise antes. Os itens vão para o Lixo, não são apagados."
        ),
        CleanTarget(
            id: "iosBackups",
            title: "Backups de iPhone/iPad",
            detail: "Backups locais feitos pelo Finder.",
            icon: "externaldrive.badge.timemachine",
            paths: ["~/Library/Application Support/MobileSync/Backup"],
            mode: .trash,
            selectedByDefault: false,
            warning: "Só remova se tiver backup no iCloud ou não precisar mais dele."
        ),
    ]
}

struct CleanItem: Identifiable {
    let url: URL
    let size: Int64
    var isSelected: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var location: String { url.deletingLastPathComponent().path.abbreviatingHome }
}

enum CleanScanner {
    struct Outcome {
        var items: [CleanItem] = []
        var errors: [String] = []
        var needsFullDiskAccess = false
    }

    static func scan(_ target: CleanTarget) -> Outcome {
        let fileManager = FileManager.default
        var outcome = Outcome()
        let cutoff = target.minimumAgeDays.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        let dateKeys: Set<URLResourceKey> = [.addedToDirectoryDateKey, .contentModificationDateKey]

        for rawPath in target.paths {
            let root = URL(fileURLWithPath: rawPath.expandingTilde, isDirectory: true)
            guard fileManager.fileExists(atPath: root.path) else { continue }

            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: Array(dateKeys),
                    options: []
                )
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError {
                    outcome.needsFullDiskAccess = true
                }
                outcome.errors.append("\(rawPath): \(error.localizedDescription)")
                continue
            }

            for child in children {
                let name = child.lastPathComponent
                if name == ".DS_Store" || name == ".localized" || target.excludedNames.contains(name) {
                    continue
                }
                if let cutoff {
                    let values = try? child.resourceValues(forKeys: dateKeys)
                    let date = values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast
                    if date > cutoff { continue }
                }
                let size = FileScanner.allocatedSize(of: child)
                guard size > 0 else { continue }
                outcome.items.append(CleanItem(url: child, size: size, isSelected: target.selectedByDefault))
            }
        }

        outcome.items.sort { $0.size > $1.size }
        return outcome
    }

    static func remove(_ url: URL, mode: RemovalMode) throws {
        switch mode {
        case .delete:
            try FileManager.default.removeItem(at: url)
        case .trash:
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }
}

enum MaintenanceAction: String, CaseIterable, Identifiable {
    case purgeMemory
    case flushDNS
    case emptyTrash
    case deleteSnapshots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .purgeMemory: "Liberar memória inativa"
        case .flushDNS: "Limpar cache de DNS"
        case .emptyTrash: "Esvaziar Lixeira (via Finder)"
        case .deleteSnapshots: "Remover snapshots locais do Time Machine"
        }
    }

    var detail: String {
        switch self {
        case .purgeMemory: "Força o macOS a descartar a memória em cache. Útil após fechar apps pesados."
        case .flushDNS: "Resolve sites que não carregam após mudanças de rede ou DNS."
        case .emptyTrash: "Funciona mesmo sem Acesso Total ao Disco. Não pode ser desfeito."
        case .deleteSnapshots: "Snapshots locais ocupam espaço \"purgeável\". Backups no disco externo continuam intactos."
        }
    }

    var icon: String {
        switch self {
        case .purgeMemory: "memorychip"
        case .flushDNS: "network"
        case .emptyTrash: "trash.slash"
        case .deleteSnapshots: "clock.arrow.circlepath"
        }
    }

    var requiresAdministrator: Bool { self != .emptyTrash }

    func perform() -> Shell.Result {
        switch self {
        case .purgeMemory:
            Shell.runAsAdministrator("/usr/sbin/purge")
        case .flushDNS:
            Shell.runAsAdministrator("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder")
        case .emptyTrash:
            Shell.runAppleScript("tell application \"Finder\" to empty trash")
        case .deleteSnapshots:
            Shell.runAsAdministrator("/usr/bin/tmutil deletelocalsnapshots /")
        }
    }
}
