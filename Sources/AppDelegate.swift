import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
        print("[BackdropPlayer] Started successfully in menu bar.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        BackdropLibraryService.shared.stopWatching()
    }
}
