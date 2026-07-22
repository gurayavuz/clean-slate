import AppKit
import SwiftUI

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("How Clean Slate works").font(.title3.weight(.semibold))
                    Text("Deleting an app leaves its files behind. This finds them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    step(1, "Give it an app",
                         "Drag any app onto the window, or use Choose Application… " +
                         "Nothing is deleted at this point — it only looks.")

                    step(2, "See what it found",
                         "Leftovers are grouped by kind, biggest first. Each one is " +
                         "labelled by how sure Clean Slate is that it belongs to that app:")
                    confidenceKey

                    step(3, "Pick what goes",
                         "Only Certain items are ticked to start with. All, Certain and " +
                         "None re-select in bulk. Hover any row to see why it matched, or " +
                         "use the arrow button to open it in Finder first.")

                    step(4, "Remove it",
                         "Items go to the Trash, so a mistake is recoverable. Permanent " +
                         "deletion is available under Options in the bottom-left, and " +
                         "always asks first.")

                    Divider()

                    note("lock.shield.fill", .orange, "Full Disk Access",
                         "macOS hides some folders — containers especially — from apps " +
                         "that haven't been granted access. Without it Clean Slate will " +
                         "miss things, and says so when it does.") {
                        Button("Open Privacy Settings") {
                            let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
                            NSWorkspace.shared.open(url)
                        }
                        .controlSize(.small)
                    }

                    note("lock.fill", .secondary, "Files needing an administrator",
                         "Anything in the system folders is listed but never touched. " +
                         "Clean Slate shows you a command to review and run yourself.") {
                        EmptyView()
                    }

                    note("menubar.arrow.up.rectangle", .secondary, "It stays in the menu bar",
                         "Closing the window doesn't quit. Clean Slate waits in the menu " +
                         "bar under ✨, where you can reopen it, start a scan, turn " +
                         "Open at Login on or off, or quit for real.") {
                        EmptyView()
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Got It") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
    }

    private func step(_ number: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var confidenceKey: some View {
        VStack(alignment: .leading, spacing: 6) {
            key(.high,   "Names the app exactly — its bundle ID or its own container.")
            key(.medium, "Strongly associated, but matched less precisely.")
            key(.low,    "A name or vendor guess. Could belong to another app — check it.")
        }
        .padding(10)
        .background { RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)) }
        .padding(.leading, 29)
    }

    private func key(_ confidence: Confidence, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ConfidenceBadge(confidence: confidence)
                .frame(width: 58, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note<Action: View>(
        _ symbol: String,
        _ tint: Color,
        _ title: String,
        _ body: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 19)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
    }
}
