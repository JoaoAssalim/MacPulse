import Observation

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview
    case disks
    case cleaner
    case processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Visão Geral"
        case .disks: "Discos"
        case .cleaner: "Limpeza"
        case .processes: "Processos"
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .disks: "internaldrive"
        case .cleaner: "sparkles"
        case .processes: "cpu"
        }
    }
}

@MainActor
@Observable
final class AppState {
    var selection: SidebarItem? = .overview
}
