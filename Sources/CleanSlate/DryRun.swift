import Foundation

/// `"/Applications/Clean Slate.app/Contents/MacOS/CleanSlate" --scan /Applications/Foo.app`
/// Prints what the GUI would offer, and deletes nothing. Purely for verifying matches.
enum DryRun {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--scan"), i + 1 < args.count else { return }

        let path = args[i + 1]
        guard let target = TargetApp(url: URL(fileURLWithPath: path)) else {
            FileHandle.standardError.write(Data("not an app bundle: \(path)\n".utf8))
            exit(1)
        }

        print("\(target.name)  [\(target.bundleID ?? "no bundle id")]")
        print("  name matching: \(target.nameIsSafeToMatch ? "on" : "off (name too short or generic)")")
        print("")

        let result = Scanner.scan(target)
        for item in result.leftovers {
            let mark = item.domain == .system ? "root" : (item.confidence == .high ? " ✓  " : "    ")
            print(String(format: "%@ %-9@ %10@  %@",
                         mark, item.confidence.label, formatBytes(item.size), item.displayPath))
            print("            \(item.reason)")
        }

        let total = result.leftovers.reduce(0) { $0 + $1.size }
        print("\n\(result.leftovers.count) items, \(formatBytes(total))")
        if !result.unreadable.isEmpty {
            print("\(result.unreadable.count) folders unreadable (needs Full Disk Access)")
            for url in result.unreadable { print("    \(url.path)") }
        }
        exit(0)
    }
}
