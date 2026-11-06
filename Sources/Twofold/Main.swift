import AppKit

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-unfold"), i + 1 < args.count {
            _ = NSApplication.shared
            DevRender.unfold(to: URL(fileURLWithPath: args[i + 1]))
            return
        }
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            _ = NSApplication.shared
            DevRender.icon(to: URL(fileURLWithPath: args[i + 1]))
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusController()
        // Reading Bluetooth may wait on the permission prompt; show the item first.
        DispatchQueue.main.async { [weak self] in
            SystemState.shared.start()
            Moments.shared.start { moment in self?.status?.show(moment) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show()
        return true
    }
}
