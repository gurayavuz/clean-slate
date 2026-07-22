import AppKit
import Foundation

struct RemovalReport {
    var trashed: [Leftover] = []
    var failed: [(Leftover, String)] = []
    var needsRoot: [Leftover] = []

    var bytesFreed: Int64 { trashed.reduce(0) { $0 + $1.size } }
}

enum Trasher {

    /// Moves user-domain items to the Trash. System-domain items are never touched —
    /// they come back in `needsRoot` so the UI can hand the user a command instead.
    static func remove(_ items: [Leftover], hardDelete: Bool) -> RemovalReport {
        var report = RemovalReport()
        let fm = FileManager.default

        for item in items {
            guard item.domain != .system else {
                report.needsRoot.append(item)
                continue
            }
            // Re-check here too: the scanner already filtered, but this is the
            // only place that actually destroys anything.
            guard Scanner.isSafeToOffer(item.url) else {
                report.failed.append((item, "Refused: protected location"))
                continue
            }
            do {
                if hardDelete {
                    try fm.removeItem(at: item.url)
                } else {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                }
                report.trashed.append(item)
            } catch {
                report.failed.append((item, error.localizedDescription))
            }
        }
        return report
    }

    /// The app has to be quit before we pull its bundle out from under it.
    static func runningInstances(of target: TargetApp) -> [NSRunningApplication] {
        guard let bid = target.bundleID else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bid)
    }

    static func quit(_ apps: [NSRunningApplication]) {
        for app in apps { app.terminate() }
    }

    /// A copy-pasteable command for the paths we refuse to delete ourselves.
    /// Launch jobs get unloaded before their plists are removed.
    static func rootCommand(for items: [Leftover]) -> String {
        guard !items.isEmpty else { return "" }
        var lines: [String] = []

        let launchJobs = items.filter {
            $0.category.hasPrefix("Launch") && $0.url.pathExtension == "plist"
        }
        for job in launchJobs {
            lines.append("sudo launchctl bootout system \(quoted(job.url.path)) 2>/dev/null")
        }

        let paths = items.map { quoted($0.url.path) }.joined(separator: " \\\n     ")
        lines.append("sudo rm -rf \\\n     \(paths)")
        return lines.joined(separator: "\n")
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
