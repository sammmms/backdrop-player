import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusBarController = StatusBarController()
        print("[BackdropPlayer] Started successfully in menu bar.")

        setupDistributedNotifications()
        handleCommandLineArguments()
    }

    private func setupDistributedNotifications() {
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(
            self,
            selector: #selector(handleShowGallery),
            name: NSNotification.Name("com.cindori.BackdropPlayer.OpenGallery"),
            object: nil
        )
        dc.addObserver(
            self,
            selector: #selector(handleSetDesktopNotification(_:)),
            name: NSNotification.Name("com.cindori.BackdropPlayer.SetDesktop"),
            object: nil
        )
        dc.addObserver(
            self,
            selector: #selector(handleSetLockScreenNotification(_:)),
            name: NSNotification.Name("com.cindori.BackdropPlayer.SetLockScreen"),
            object: nil
        )
        dc.addObserver(
            self,
            selector: #selector(handleSetBothNotification(_:)),
            name: NSNotification.Name("com.cindori.BackdropPlayer.SetBoth"),
            object: nil
        )
    }

    private func handleCommandLineArguments() {
        let args = CommandLine.arguments

        if args.contains("--gallery") {
            GalleryWindowController.shared.show()
        }

        if let idx = args.firstIndex(of: "--set-desktop"), idx + 1 < args.count {
            let targetTitle = args[idx + 1]
            applyWallpaperByTitle(targetTitle, target: .desktop)
        }

        if let idx = args.firstIndex(of: "--set-lock"), idx + 1 < args.count {
            let targetTitle = args[idx + 1]
            applyWallpaperByTitle(targetTitle, target: .lockScreen)
        }

        if let idx = args.firstIndex(of: "--set-both"), idx + 1 < args.count {
            let targetTitle = args[idx + 1]
            applyWallpaperByTitle(targetTitle, target: .both)
        }
    }

    private enum WallpaperTarget {
        case desktop
        case lockScreen
        case both
    }

    private func applyWallpaperByTitle(_ query: String, target: WallpaperTarget) {
        let wallpapers = BackdropLibraryService.shared.fetchWallpapers()
        if let match = wallpapers.first(where: { $0.title.lowercased().contains(query.lowercased()) }) {
            switch target {
            case .desktop:
                WallpaperEngine.shared.setDesktopWallpaper(match)
            case .lockScreen:
                WallpaperEngine.shared.setLockScreenWallpaper(match)
            case .both:
                WallpaperEngine.shared.setBothWallpapers(match)
            }
        }
    }

    @objc private func handleShowGallery() {
        DispatchQueue.main.async {
            GalleryWindowController.shared.show()
        }
    }

    @objc private func handleSetDesktopNotification(_ notif: Notification) {
        guard let title = notif.userInfo?["title"] as? String else { return }
        DispatchQueue.main.async {
            self.applyWallpaperByTitle(title, target: .desktop)
        }
    }

    @objc private func handleSetLockScreenNotification(_ notif: Notification) {
        guard let title = notif.userInfo?["title"] as? String else { return }
        DispatchQueue.main.async {
            self.applyWallpaperByTitle(title, target: .lockScreen)
        }
    }

    @objc private func handleSetBothNotification(_ notif: Notification) {
        guard let title = notif.userInfo?["title"] as? String else { return }
        DispatchQueue.main.async {
            self.applyWallpaperByTitle(title, target: .both)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        GalleryWindowController.shared.show()
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    public func applicationWillTerminate(_ notification: Notification) {
        BackdropLibraryService.shared.stopWatching()
    }
}
