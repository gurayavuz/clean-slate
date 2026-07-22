import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct CleanSlateApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var loginItem = LoginItem()

    init() {
        DryRun.runIfRequested()
        LoginItem.handleCommandLine()
    }

    var body: some Scene {
        // A single Window, not a WindowGroup: closing it leaves the app alive in
        // the menu bar instead of ending the session.
        Window("Clean Slate", id: Self.mainWindowID) {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 620, minHeight: 480)
                .onAppear {
                    installKeyEquivalents()
                    suppressWindowIfLaunchedAtLogin()
                }
        }
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) {} }

        MenuBarExtra("Clean Slate", systemImage: "sparkles") {
            MenuBarContent()
                .environmentObject(model)
                .environmentObject(loginItem)
        }
    }

    static let mainWindowID = "main"

    /// An LSUIElement app has no application menu, so the shortcuts every Mac
    /// window is expected to answer have to be handled by hand.
    private func installKeyEquivalents() {
        guard !Self.keyEquivalentsInstalled else { return }
        Self.keyEquivalentsInstalled = true

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "q": NSApp.terminate(nil); return nil
            case "w": NSApp.keyWindow?.performClose(nil); return nil
            default:  return event
            }
        }
    }

    private static var keyEquivalentsInstalled = false

    /// Launching at login shouldn't throw a window in your face at every boot.
    /// A login launch never activates the app, whereas double-clicking always
    /// does — so an app that still isn't frontmost a moment after appearing was
    /// started by launchd, and the window closes back into the menu bar.
    private func suppressWindowIfLaunchedAtLogin() {
        guard !NSApp.isActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard !NSApp.isActive else { return }
            // SwiftUI decorates the scene id, so match loosely and fall back to
            // the one window that can become main (the menu bar extra can't).
            let byID = NSApp.windows.first { $0.identifier?.rawValue.contains(Self.mainWindowID) ?? false }
            (byID ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain })?.close()
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loginItem: LoginItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Clean Slate") { showWindow() }
            .keyboardShortcut("o")

        Button("Choose Application…") {
            showWindow()
            chooseApp()
        }

        Button("How It Works") {
            showWindow()
            model.showHelp = true
        }

        Divider()

        Toggle("Open at Login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.set($0) }
        ))

        if let failure = loginItem.failure {
            Text("Login item failed: \(failure)")
        }

        Divider()

        Button("Quit Clean Slate") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// From an accessory app the window comes up behind everything unless we
    /// activate first, so order matters here.
    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: CleanSlateApp.mainWindowID)
        loginItem.refresh()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { model.inspect(url) }
    }
}
