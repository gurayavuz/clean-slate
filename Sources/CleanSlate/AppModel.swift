import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {

    enum Phase {
        case idle
        case scanning(String)
        case results
        case finished(RemovalReport)
    }

    @Published var phase: Phase = .idle
    @Published var target: TargetApp?
    @Published var leftovers: [Leftover] = []
    @Published var selected: Set<UUID> = []
    /// System items are tracked apart from `selected` so they can never reach the
    /// Trash flow's counts or its delete call — they only ever build a command
    /// the user reviews and runs themselves.
    @Published var systemSelected: Set<UUID> = []
    @Published var unreadable: [URL] = []
    @Published var hardDelete = false
    @Published var errorMessage: String?
    /// Lives on the model rather than a view because both the idle screen and
    /// the menu bar open the same guide.
    @Published var showHelp = false

    var selectedItems: [Leftover] { leftovers.filter { selected.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    /// Uncertain matches selected for removal. Called out before anything is
    /// destroyed, because these are the ones that may belong to a different app.
    var selectedUncertain: [Leftover] { selectedItems.filter { $0.confidence == .low } }

    var selectedSystemItems: [Leftover] {
        leftovers.filter { $0.domain == .system && systemSelected.contains($0.id) }
    }

    // MARK: - Scanning

    func inspect(_ url: URL) {
        guard let target = TargetApp(url: url) else {
            errorMessage = "\(url.lastPathComponent) isn't an application bundle."
            return
        }
        errorMessage = nil
        self.target = target
        phase = .scanning(target.name)

        Task.detached(priority: .userInitiated) {
            let result = Scanner.scan(target)
            await MainActor.run {
                self.leftovers = result.leftovers
                self.unreadable = result.unreadable
                // Conservative default in both lists: only certain matches start
                // checked, and a root command starts out empty of guesses.
                self.selected = Set(result.leftovers
                    .filter { $0.domain != .system && $0.confidence == .high }.map(\.id))
                self.systemSelected = Set(result.leftovers
                    .filter { $0.domain == .system && $0.confidence == .high }.map(\.id))
                self.phase = .results
            }
        }
    }

    func reset() {
        phase = .idle
        target = nil
        leftovers = []
        selected = []
        systemSelected = []
        unreadable = []
        errorMessage = nil
    }

    // MARK: - Removal

    /// Non-nil when the target app is still running and must be quit first.
    var runningInstances: [NSRunningApplication] {
        guard let target else { return [] }
        return Trasher.runningInstances(of: target)
    }

    func performRemoval() {
        let running = runningInstances
        if !running.isEmpty { Trasher.quit(running) }

        let items = selectedItems
        let hard = hardDelete
        Task.detached(priority: .userInitiated) {
            let report = Trasher.remove(items, hardDelete: hard)
            await MainActor.run { self.phase = .finished(report) }
        }
    }

    func toggle(_ item: Leftover) {
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }

    func setAll(_ on: Bool, where predicate: (Leftover) -> Bool) {
        for item in leftovers where predicate(item) {
            if on { selected.insert(item.id) } else { selected.remove(item.id) }
        }
    }

    func toggleSystem(_ item: Leftover) {
        if systemSelected.contains(item.id) {
            systemSelected.remove(item.id)
        } else {
            systemSelected.insert(item.id)
        }
    }

    func setAllSystem(_ on: Bool, where predicate: (Leftover) -> Bool = { _ in true }) {
        for item in leftovers where item.domain == .system && predicate(item) {
            if on { systemSelected.insert(item.id) } else { systemSelected.remove(item.id) }
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
