import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .idle:                 DropView()
            case .scanning(let name):   ScanningView(appName: name)
            case .results:              ResultsView()
            case .finished(let report): FinishedView(report: report)
            }
        }
        .sheet(isPresented: $model.showHelp) { HelpSheet() }
    }
}

// MARK: - Drop target

struct DropView: View {
    @EnvironmentObject var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            dropZone

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: model.errorMessage)
    }

    /// A bounded, dashed target — the window accepts drops anywhere, but the
    /// affordance has to look like something you can drop onto.
    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.app.fill" : "arrow.down.app")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Drop an application here")
                    .font(.title2.weight(.medium))
                Text("Clean Slate finds what it left behind — preferences, caches,\ncontainers, launch agents — and shows you before deleting anything.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button("Choose Application…") { chooseApp() }
                    .controlSize(.large)
                Button("How It Works") { model.showHelp = true }
                    .controlSize(.large)
            }
            .padding(.top, 2)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.30),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.inspect(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { model.inspect(url) }
    }
}

struct ScanningView: View {
    let appName: String
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Searching for traces of \(appName)…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Results

struct ResultsView: View {
    @EnvironmentObject var model: AppModel
    @State private var showRootCommand = false
    @State private var confirmingRemoval = false

    private var userItems: [Leftover] { model.leftovers.filter { $0.domain != .system } }
    private var systemItems: [Leftover] { model.leftovers.filter { $0.domain == .system } }

    /// Biggest category first — the 3 GB container should never be below the 4 KB plist.
    private var groups: [(category: String, items: [Leftover])] {
        Dictionary(grouping: userItems, by: \.category)
            .map { (category: $0.key, items: $0.value.sorted { $0.size > $1.size }) }
            .sorted { bytes($0.items) > bytes($1.items) }
    }

    private func bytes(_ items: [Leftover]) -> Int64 { items.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if userItems.isEmpty && systemItems.isEmpty {
                emptyState
            } else {
                List {
                    if !model.unreadable.isEmpty {
                        fullDiskAccessBanner
                            .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 10, trailing: 6))
                    }

                    ForEach(groups, id: \.category) { group in
                        Section {
                            ForEach(group.items) { item in
                                LeftoverRow(item: item, isOn: model.selected.contains(item.id)) {
                                    model.toggle(item)
                                }
                            }
                        } header: {
                            categoryHeader(group.category, items: group.items)
                        }
                    }

                    if !systemItems.isEmpty {
                        Section {
                            ForEach(systemItems) { item in
                                LeftoverRow(item: item, isOn: model.systemSelected.contains(item.id)) {
                                    model.toggleSystem(item)
                                }
                            }
                            HStack {
                                Button("Show removal command…") { showRootCommand = true }
                                    .disabled(model.selectedSystemItems.isEmpty)
                                Text("\(model.selectedSystemItems.count) of \(systemItems.count) will be included")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill").font(.caption2)
                                Text("Needs administrator — Clean Slate won't touch these")
                                Spacer()
                                Button("All") { model.setAllSystem(true) }
                                Button("None") { model.setAllSystem(false) }
                                Text(formatBytes(bytes(systemItems)))
                                    .monospacedDigit()
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
                .environment(\.defaultMinListRowHeight, 34)
            }

            Divider()
            footer
        }
        .sheet(isPresented: $showRootCommand) {
            RootCommandSheet(
                command: Trasher.rootCommand(for: model.selectedSystemItems),
                uncertain: model.selectedSystemItems.filter { $0.confidence == .low }.count
            )
        }
        .confirmationDialog(
            model.hardDelete ? "Permanently delete \(model.selected.count) items?" : "Move \(model.selected.count) items to the Trash?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(model.hardDelete ? "Delete Permanently" : "Move to Trash", role: .destructive) {
                model.performRemoval()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    /// "Possible" matches are name or vendor guesses, so a sibling app's data can
    /// end up selected — most easily via the All button. Say so at the last
    /// moment, where it can still change the outcome.
    private var confirmationMessage: String {
        var lines = [
            model.hardDelete
                ? "This frees \(formatBytes(model.selectedBytes)) and cannot be undone."
                : "This frees \(formatBytes(model.selectedBytes)). You can restore them from the Trash."
        ]
        let uncertain = model.selectedUncertain.count
        if uncertain > 0 {
            lines.append("\(uncertain) of them are Possible matches only — they may belong to a different app.")
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if let target = model.target {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: target.url.path))
                        .resizable()
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.name).font(.title3.weight(.semibold))
                        Text(target.bundleID ?? "no bundle identifier")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Choose Another…") { model.reset() }
                    .controlSize(.small)
                Button {
                    model.showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("How Clean Slate works")
            }

            if !userItems.isEmpty {
                HStack(spacing: 8) {
                    Text("\(userItems.count) items · \(formatBytes(bytes(userItems))) found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Select")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Certain") {
                        model.setAll(false) { $0.domain != .system }
                        model.setAll(true) { $0.domain != .system && $0.confidence == .high }
                    }
                    Button("All") { model.setAll(true) { $0.domain != .system } }
                    Button("None") { model.setAll(false) { $0.domain != .system } }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func categoryHeader(_ category: String, items: [Leftover]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon(for: category))
                .font(.caption)
                .frame(width: 14)
            Text(category)
            Text("\(items.count)")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            Spacer()
            Text(formatBytes(bytes(items)))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing left behind")
                .font(.title3.weight(.medium))
            Text("\(model.target?.name ?? "This app") didn't leave any traces we can find.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fullDiskAccessBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(model.unreadable.count) folders couldn't be read")
                    .font(.callout.weight(.medium))
                Text("Grant Clean Slate Full Disk Access to search them — there may be more to find.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Open Settings") {
                let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
                NSWorkspace.shared.open(url)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.10))
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Menu {
                Toggle("Delete permanently (skip Trash)", isOn: $model.hardDelete)
            } label: {
                Label("Options", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if model.hardDelete {
                Label("Permanent — no Trash", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(formatBytes(model.selectedBytes))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(model.selected.count) of \(userItems.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(model.hardDelete ? "Delete…" : "Move to Trash…") {
                confirmingRemoval = true
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.selected.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.15), value: model.selectedBytes)
    }

    private func icon(for category: String) -> String {
        switch category {
        case "Application":                       "app.fill"
        case "Preferences", "Preferences (ByHost)": "slider.horizontal.3"
        case "Caches":                            "clock.arrow.circlepath"
        case "Application Support":               "folder.fill"
        case "Container", "Group Container":      "shippingbox.fill"
        case "Launch Agent", "Launch Daemon":     "bolt.fill"
        case "Logs":                              "doc.text.fill"
        case "Saved State", "Autosave":           "macwindow"
        case "Cookies", "Web Storage", "WebKit Data": "network"
        case "Privileged Helper":                 "key.fill"
        case "Kernel Extension":                  "cpu.fill"
        case "Plug-In":                           "puzzlepiece.extension.fill"
        case "Installer Receipt":                 "receipt.fill"
        case "App Scripts", "Service":            "gearshape.fill"
        default:                                  "folder"
        }
    }
}

struct LeftoverRow: View {
    let item: Leftover
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isOn }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()

            Text(item.displayPath)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            ConfidenceBadge(confidence: item.confidence)

            Spacer(minLength: 8)

            Text(formatBytes(item.size))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .help(item.reason)
        .padding(.vertical, 1)
    }
}

/// Uncertainty is not an error, so nothing here is red — red is reserved for
/// failures. Low confidence simply recedes.
struct ConfidenceBadge: View {
    let confidence: Confidence

    var body: some View {
        Text(confidence.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch confidence {
        case .high:   .green
        case .medium: .orange
        case .low:    .secondary
        }
    }
}

struct RootCommandSheet: View {
    let command: String
    var uncertain = 0
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run this in Terminal").font(.headline)
            Text("Clean Slate doesn't delete system files itself. Review these paths before running.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Running `rm -rf` as root on a guessed path is the least forgiving
            // thing this app can lead someone into. Name the risk here.
            if uncertain > 0 {
                Label(
                    "\(uncertain) of these are uncertain matches and may belong to another app. Deleting them as an administrator cannot be undone — check each path first.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack {
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                }
                .disabled(copied)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 560)
    }
}

// MARK: - Done

struct FinishedView: View {
    @EnvironmentObject var model: AppModel
    let report: RemovalReport

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white, .green)

            VStack(spacing: 4) {
                Text(formatBytes(report.bytesFreed))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("freed from \(report.trashed.count) items")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !report.failed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(report.failed.count) items couldn't be removed", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                    ForEach(report.failed, id: \.0.id) { item, message in
                        Text("\(item.displayPath) — \(message)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .frame(maxWidth: 460, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10))
                }
            }

            Button("Remove Another App") { model.reset() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
