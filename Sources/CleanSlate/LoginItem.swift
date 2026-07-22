import AppKit
import ServiceManagement
import SwiftUI

/// Registers the app itself as a login item via `SMAppService` — no helper
/// bundle, no launchd plist to install. macOS keys the registration to the code
/// signature, so it survives rebuilds only while the signing identity is stable
/// (see build.sh); it does *not* survive moving the .app to a different folder.
@MainActor
final class LoginItem: ObservableObject {

    @Published private(set) var isEnabled: Bool
    /// Surfaced in the menu when macOS refuses the registration, rather than
    /// silently leaving the toggle in a state that isn't real.
    @Published var failure: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        // Trust the system's answer over our request — if registration was
        // refused, the toggle must snap back.
        refresh()
    }

    /// Login-item status is also reachable from the command line for verifying a
    /// build without clicking through the menu: `CleanSlate --login-item status`.
    nonisolated static func handleCommandLine() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--login-item") else { return }
        let verb = i + 1 < args.count ? args[i + 1] : "status"

        func describe(_ s: SMAppService.Status) -> String {
            switch s {
            case .enabled:        "enabled"
            case .notRegistered:  "not registered"
            case .notFound:       "not found"
            case .requiresApproval: "requires approval in System Settings > General > Login Items"
            @unknown default:     "unknown (\(s.rawValue))"
            }
        }

        do {
            switch verb {
            case "on":  try SMAppService.mainApp.register()
            case "off": try SMAppService.mainApp.unregister()
            case "status": break
            default:
                FileHandle.standardError.write(Data("usage: --login-item [on|off|status]\n".utf8))
                exit(1)
            }
        } catch {
            FileHandle.standardError.write(Data("\(verb) failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }

        print("login item: \(describe(SMAppService.mainApp.status))")
        exit(0)
    }
}
