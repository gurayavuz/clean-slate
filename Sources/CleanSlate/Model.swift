import Foundation

/// How sure we are that a found path really belongs to the target app.
/// Only `.high` is pre-selected for removal.
enum Confidence: Int, Comparable, CaseIterable {
    case low = 0      // name-substring or vendor-prefix guess — could belong to a sibling app
    case medium = 1   // bundle-id prefixed, or an exact app-name folder
    case high = 2     // exact bundle-id match, or the app's own container

    static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .high: "Certain"
        case .medium: "Likely"
        case .low: "Possible"
        }
    }
}

/// Which privilege domain a path lives in. System paths are reported, never deleted by the app.
enum Domain {
    case app        // the .app bundle itself
    case user       // ~/Library/... — deletable by us
    case system     // /Library/... — needs root, we only report
}

struct Leftover: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let category: String       // e.g. "Preferences", "Caches"
    let confidence: Confidence
    let domain: Domain
    let reason: String         // why we matched it — shown on hover
    var size: Int64 = 0

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    static func == (a: Leftover, b: Leftover) -> Bool { a.url == b.url }
    func hash(into h: inout Hasher) { h.combine(url) }
}

/// The app we've been asked to remove, plus the keys we search leftovers by.
struct TargetApp {
    let url: URL
    let name: String            // "Foo" — from CFBundleName, else the filename
    let bundleID: String?       // "com.vendor.foo"
    let executable: String?

    /// "com.vendor" — used only for low-confidence matches.
    var vendorPrefix: String? {
        guard let bundleID else { return nil }
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts.prefix(2).joined(separator: ".")
    }

    /// Short or generic names produce garbage matches ("Mail", "Go", "Books"),
    /// so we refuse to search by name at all in those cases.
    var nameIsSafeToMatch: Bool {
        guard name.count >= 4 else { return false }
        return !Self.genericNames.contains(name.lowercased())
    }

    private static let genericNames: Set<String> = [
        "mail", "music", "notes", "photos", "maps", "news", "home", "books",
        "files", "player", "video", "audio", "chat", "cloud", "sync", "setup",
        "installer", "updater", "helper", "agent", "service", "system", "utility"
    ]

    init?(url: URL) {
        guard url.pathExtension == "app" else { return nil }
        self.url = url
        let plist = url.appendingPathComponent("Contents/Info.plist")
        let dict = NSDictionary(contentsOf: plist) as? [String: Any] ?? [:]
        self.bundleID = dict["CFBundleIdentifier"] as? String
        self.executable = dict["CFBundleExecutable"] as? String
        let fallback = url.deletingPathExtension().lastPathComponent
        self.name = (dict["CFBundleName"] as? String)?.nilIfEmpty ?? fallback
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
