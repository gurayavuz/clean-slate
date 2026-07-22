import Foundation

struct ScanResult {
    var leftovers: [Leftover] = []
    /// Directories we couldn't list — almost always a Full Disk Access problem.
    var unreadable: [URL] = []
}

enum Scanner {

    // MARK: - Where leftovers hide

    private struct Location {
        let path: String
        let category: String
        let domain: Domain
        /// Preferences/ByHost stores `com.vendor.foo.<UUID>.plist`, so we trim a trailing UUID.
        var stripsHostSuffix: Bool = false
    }

    private static var userLocations: [Location] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func lib(_ sub: String) -> String { "\(home)/Library/\(sub)" }
        return [
            .init(path: lib("Application Support"),      category: "Application Support", domain: .user),
            .init(path: lib("Caches"),                   category: "Caches",              domain: .user),
            .init(path: lib("Preferences"),              category: "Preferences",         domain: .user),
            .init(path: lib("Preferences/ByHost"),       category: "Preferences (ByHost)", domain: .user, stripsHostSuffix: true),
            .init(path: lib("Containers"),               category: "Container",           domain: .user),
            .init(path: lib("Group Containers"),         category: "Group Container",     domain: .user),
            .init(path: lib("Saved Application State"),  category: "Saved State",         domain: .user),
            .init(path: lib("HTTPStorages"),             category: "Web Storage",         domain: .user),
            .init(path: lib("WebKit"),                   category: "WebKit Data",         domain: .user),
            .init(path: lib("Cookies"),                  category: "Cookies",             domain: .user),
            .init(path: lib("Logs"),                     category: "Logs",                domain: .user),
            .init(path: lib("LaunchAgents"),             category: "Launch Agent",        domain: .user),
            .init(path: lib("Application Scripts"),      category: "App Scripts",         domain: .user),
            .init(path: lib("Autosave Information"),     category: "Autosave",            domain: .user),
            .init(path: lib("Internet Plug-Ins"),        category: "Plug-In",             domain: .user),
            .init(path: lib("Services"),                 category: "Service",             domain: .user),
        ]
    }

    private static let systemLocations: [Location] = [
        .init(path: "/Library/Application Support",   category: "Application Support", domain: .system),
        .init(path: "/Library/Caches",                category: "Caches",              domain: .system),
        .init(path: "/Library/Preferences",           category: "Preferences",         domain: .system),
        .init(path: "/Library/LaunchAgents",          category: "Launch Agent",        domain: .system),
        .init(path: "/Library/LaunchDaemons",         category: "Launch Daemon",       domain: .system),
        .init(path: "/Library/PrivilegedHelperTools", category: "Privileged Helper",   domain: .system),
        .init(path: "/Library/Extensions",            category: "Kernel Extension",    domain: .system),
        .init(path: "/Library/Internet Plug-Ins",     category: "Plug-In",             domain: .system),
        .init(path: "/private/var/db/receipts",       category: "Installer Receipt",   domain: .system),
    ]

    /// Dotfile homes. Matched on a stricter rule than the Library folders because
    /// a stray `~/.foo` hit is more likely to be an unrelated tool's config.
    private static var dotLocations: [(path: String, category: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            (home, "Home Dotfile"),
            ("\(home)/.config", "Config"),
            ("\(home)/.cache", "Cache"),
            ("\(home)/.local/share", "Local Data"),
        ]
    }

    // MARK: - Scan

    static func scan(_ target: TargetApp) -> ScanResult {
        var result = ScanResult()

        // The bundle itself always goes first.
        result.leftovers.append(
            Leftover(url: target.url, category: "Application", confidence: .high,
                     domain: .app, reason: "The application bundle")
        )

        let fm = FileManager.default
        for loc in (userLocations + systemLocations) {
            let dir = URL(fileURLWithPath: loc.path)
            guard fm.fileExists(atPath: loc.path) else { continue }

            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles])
            } catch {
                result.unreadable.append(dir)
                continue
            }

            for child in children {
                guard let (confidence, reason) = classify(child.lastPathComponent,
                                                          against: target,
                                                          stripHostSuffix: loc.stripsHostSuffix)
                else { continue }
                result.leftovers.append(
                    Leftover(url: child, category: loc.category,
                             confidence: confidence, domain: loc.domain, reason: reason)
                )
            }
        }

        // Dotfiles: only in the home root do we require a leading dot, since
        // entries inside ~/.config are already scoped.
        for loc in dotLocations {
            let dir = URL(fileURLWithPath: loc.path)
            guard let children = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: []) else { continue }

            for child in children {
                let raw = child.lastPathComponent
                let isHome = loc.path == FileManager.default.homeDirectoryForCurrentUser.path
                if isHome && !raw.hasPrefix(".") { continue }
                let stem = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
                guard let reason = matchesDotEntry(stem, target) else { continue }
                result.leftovers.append(
                    Leftover(url: child, category: loc.category,
                             confidence: .medium, domain: .user, reason: reason)
                )
            }
        }

        result.leftovers = result.leftovers.filter { isSafeToOffer($0.url) }

        // Size up everything, biggest first within each confidence tier.
        for i in result.leftovers.indices {
            result.leftovers[i].size = diskSize(of: result.leftovers[i].url)
        }
        result.leftovers.sort {
            $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.size > $1.size
        }
        return result
    }

    // MARK: - Matching

    /// Returns nil when the name has nothing to do with the target app.
    /// This is the whole safety story of the tool, so it errs toward saying nil.
    static func classify(_ rawName: String, against target: TargetApp,
                         stripHostSuffix: Bool = false) -> (Confidence, String)? {
        var base = strippingKnownExtension(rawName)
        if stripHostSuffix { base = strippingTrailingUUID(base) }

        if let bid = target.bundleID, !bid.isEmpty {
            if base == bid {
                return (.high, "Exact bundle identifier match")
            }
            if base.hasPrefix(bid + ".") {
                return (.medium, "Name is prefixed with the app's bundle identifier")
            }
            // Group containers look like "ABCDE12345.com.vendor.foo".
            if base.hasSuffix("." + bid) {
                return (.high, "Group container for this bundle identifier")
            }
            if base.contains(bid) {
                return (.medium, "Contains the app's bundle identifier")
            }
        }

        if target.nameIsSafeToMatch {
            if base.compare(target.name, options: .caseInsensitive) == .orderedSame {
                return (.medium, "Named exactly after the app")
            }
            if base.localizedCaseInsensitiveContains(target.name) {
                return (.low, "Name contains \"\(target.name)\" — check this belongs to the app")
            }
        }

        if let vendor = target.vendorPrefix, base.hasPrefix(vendor + ".") {
            return (.low, "Same vendor prefix (\(vendor)) — may belong to another of their apps")
        }

        return nil
    }

    /// Deliberately strict: exact equality only. A dotfolder named `foo` gets removed
    /// with app "Foo", but `foo-shared` or `foobar` does not.
    private static func matchesDotEntry(_ stem: String, _ target: TargetApp) -> String? {
        if let bid = target.bundleID, stem.caseInsensitiveCompare(bid) == .orderedSame {
            return "Dotfolder named after the bundle identifier"
        }
        if target.nameIsSafeToMatch,
           stem.caseInsensitiveCompare(target.name) == .orderedSame {
            return "Dotfolder named exactly after the app"
        }
        return nil
    }

    /// Last line of defence: never offer up a container directory itself, no matter
    /// what the matcher decided.
    static func isSafeToOffer(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard path.count > 1, !protectedPaths.contains(path) else { return false }
        return true
    }

    private static let protectedPaths: Set<String> = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths: Set<String> = [
            "/", "/Applications", "/Library", "/System", "/Users", "/usr", "/private",
            "/var", "/etc", "/opt", "/bin", "/sbin", "/tmp",
            home, "\(home)/Library", "\(home)/Documents", "\(home)/Desktop",
            "\(home)/Downloads", "\(home)/Pictures", "\(home)/Music", "\(home)/Movies",
            "\(home)/.config", "\(home)/.cache", "\(home)/.local", "\(home)/.ssh",
        ]
        paths.formUnion(userLocations.map(\.path))
        paths.formUnion(systemLocations.map(\.path))
        return paths
    }()

    private static let knownExtensions: Set<String> = [
        "plist", "savedState", "bom", "app", "log", "binarycookies", "helper"
    ]

    private static func strippingKnownExtension(_ name: String) -> String {
        let url = URL(fileURLWithPath: name)
        return knownExtensions.contains(url.pathExtension)
            ? url.deletingPathExtension().lastPathComponent
            : name
    }

    /// "com.vendor.foo.A1B2C3D4-..." -> "com.vendor.foo"
    private static func strippingTrailingUUID(_ name: String) -> String {
        guard let lastDot = name.lastIndex(of: ".") else { return name }
        let tail = String(name[name.index(after: lastDot)...])
        let isHexish = tail.count >= 12 && tail.allSatisfy {
            $0.isHexDigit || $0 == "-"
        }
        return isHexish ? String(name[..<lastDot]) : name
    }

    // MARK: - Sizing

    static func diskSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }

        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                    options: [], errorHandler: { _, _ in true }) else { return 0 }
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }
}
