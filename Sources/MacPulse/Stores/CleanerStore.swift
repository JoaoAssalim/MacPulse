import Foundation
import Observation

enum SelectionState {
    case none, partial, all
}

struct CleanCategory: Identifiable {
    let target: CleanTarget
    var items: [CleanItem] = []
    var errors: [String] = []
    var needsFullDiskAccess = false
    var isExpanded = false

    var id: String { target.id }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.reduce(0) { $0 + ($1.isSelected ? $1.size : 0) } }

    var selectionState: SelectionState {
        let selected = items.filter(\.isSelected).count
        if selected == 0 { return .none }
        return selected == items.count ? .all : .partial
    }
}

struct CleanReport {
    let freed: Int64
    let removedCount: Int
    let failures: [String]
}

struct MaintenanceReport {
    let action: MaintenanceAction
    let succeeded: Bool
    let message: String
}

@MainActor
@Observable
final class CleanerStore {
    var categories: [CleanCategory] = CleanTarget.all.map { CleanCategory(target: $0) }
    private(set) var isScanning = false
    private(set) var isCleaning = false
    private(set) var hasScanned = false
    private(set) var scanningTitle: String?
    private(set) var runningMaintenance: MaintenanceAction?
    var lastReport: CleanReport?
    var maintenanceReport: MaintenanceReport?

    var totalFound: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    var totalSelected: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.items.filter(\.isSelected).count } }
    var needsFullDiskAccess: Bool { categories.contains(where: \.needsFullDiskAccess) }
    var isBusy: Bool { isScanning || isCleaning }

    func scan() async {
        guard !isBusy else { return }
        isScanning = true
        lastReport = nil

        for index in categories.indices {
            let target = categories[index].target
            scanningTitle = target.title
            let outcome = await Task.detached(priority: .userInitiated) { CleanScanner.scan(target) }.value
            categories[index].items = outcome.items
            categories[index].errors = outcome.errors
            categories[index].needsFullDiskAccess = outcome.needsFullDiskAccess
        }

        scanningTitle = nil
        isScanning = false
        hasScanned = true
    }

    func clean() async {
        guard !isBusy else { return }
        let jobs = categories.flatMap { category in
            category.items.filter(\.isSelected).map { (url: $0.url, size: $0.size, mode: category.target.mode) }
        }
        guard !jobs.isEmpty else { return }

        isCleaning = true
        let outcome = await Task.detached(priority: .userInitiated) {
            var freed: Int64 = 0
            var removed: [URL] = []
            var failures: [String] = []
            for job in jobs {
                do {
                    try CleanScanner.remove(job.url, mode: job.mode)
                    freed += job.size
                    removed.append(job.url)
                } catch {
                    failures.append("\(job.url.path.abbreviatingHome): \(error.localizedDescription)")
                }
            }
            return (freed: freed, removed: removed, failures: failures)
        }.value

        let removedSet = Set(outcome.removed)
        for index in categories.indices {
            categories[index].items.removeAll { removedSet.contains($0.url) }
        }
        lastReport = CleanReport(freed: outcome.freed, removedCount: outcome.removed.count, failures: outcome.failures)
        isCleaning = false
    }

    func setSelection(_ selected: Bool, forCategory id: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        for itemIndex in categories[index].items.indices {
            categories[index].items[itemIndex].isSelected = selected
        }
    }

    func toggleItem(_ itemID: URL, inCategory id: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }),
              let itemIndex = categories[index].items.firstIndex(where: { $0.id == itemID }) else { return }
        categories[index].items[itemIndex].isSelected.toggle()
    }

    func toggleExpanded(_ id: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].isExpanded.toggle()
    }

    func run(_ action: MaintenanceAction) async {
        guard runningMaintenance == nil else { return }
        runningMaintenance = action
        let result = await Task.detached(priority: .userInitiated) { action.perform() }.value
        runningMaintenance = nil

        let message: String
        if result.succeeded {
            message = "Concluído."
        } else if result.wasCancelledByUser {
            message = "Operação cancelada."
        } else {
            message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        maintenanceReport = MaintenanceReport(action: action, succeeded: result.succeeded, message: message)
    }
}
