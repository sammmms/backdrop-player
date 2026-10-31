import AppKit
import UniformTypeIdentifiers

public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let libraryService = BackdropLibraryService.shared
    private let engine = WallpaperEngine.shared

    private var cachedWallpapers: [WallpaperItem] = []

    public override init() {
        super.init()
        setupStatusItem()
        loadWallpapers()

        engine.onStateChange = { [weak self] in
            DispatchQueue.main.async {
                self?.rebuildMenu()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineStateNotification),
            name: NSNotification.Name("WallpaperEngineStateChanged"),
            object: nil
        )

        libraryService.startWatching { [weak self] in
            DispatchQueue.main.async {
                print("[StatusBarController] Detected Backdrop folder changes, refreshing...")
                self?.loadWallpapers()
            }
        }
    }

    @objc private func handleEngineStateNotification() {
        DispatchQueue.main.async {
            self.rebuildMenu()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: "Backdrop Player") {
                img.isTemplate = true
                button.image = img
            } else if let img = NSImage(systemSymbolName: "play.rectangle.on.rectangle", accessibilityDescription: "Backdrop Player") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "🎬"
            }
        }

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    public func loadWallpapers() {
        cachedWallpapers = libraryService.fetchWallpapers()
        print("[StatusBarController] Loaded \(cachedWallpapers.count) wallpapers from library")
        rebuildMenu()

        // 1. Restore or default Desktop wallpaper
        if engine.currentDesktopWallpaper == nil {
            let lastDesktopPath = UserDefaults.standard.string(forKey: "WallpaperEngine.desktopWallpaperPath") ??
                UserDefaults.standard.string(forKey: "WallpaperEngine.lastWallpaperPath")
            let lastDesktopId = UserDefaults.standard.string(forKey: "WallpaperEngine.desktopWallpaperId") ??
                UserDefaults.standard.string(forKey: "WallpaperEngine.lastWallpaperId")

            if let matched = cachedWallpapers.first(where: { $0.id == lastDesktopId || $0.fileURL.path == lastDesktopPath }) {
                print("[StatusBarController] Restoring Desktop wallpaper: \(matched.title)")
                engine.setDesktopWallpaper(matched)
            } else if let kirby = cachedWallpapers.first(where: { $0.title.contains("Kirby") }) {
                print("[StatusBarController] Defaulting Desktop to Kirby: \(kirby.title)")
                engine.setDesktopWallpaper(kirby)
            } else if let first = cachedWallpapers.first {
                engine.setDesktopWallpaper(first)
            }
        }

        // 2. Restore or default Lock Screen wallpaper
        if engine.currentLockScreenWallpaper == nil {
            let lastLockPath = UserDefaults.standard.string(forKey: "WallpaperEngine.lockScreenWallpaperPath")
            let lastLockId = UserDefaults.standard.string(forKey: "WallpaperEngine.lockScreenWallpaperId")

            if let matched = cachedWallpapers.first(where: { $0.id == lastLockId || $0.fileURL.path == lastLockPath }) {
                print("[StatusBarController] Restoring Lock Screen wallpaper: \(matched.title)")
                engine.setLockScreenWallpaper(matched)
            } else if let toads = cachedWallpapers.first(where: { $0.title.contains("Toad") }) {
                print("[StatusBarController] Defaulting Lock Screen to Abi Toads: \(toads.title)")
                engine.setLockScreenWallpaper(toads)
            }
        }
    }

    // MARK: - Menu Construction

    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        // 1. App Title & Status
        let titleItem = NSMenuItem(
            title: "Backdrop Player",
            action: nil,
            keyEquivalent: ""
        )
        titleItem.attributedTitle = NSAttributedString(
            string: "Backdrop Player",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        let desktopTitle = engine.currentDesktopWallpaper?.title ?? "None"
        let lockTitle = engine.currentLockScreenWallpaper?.title ??
            UserDefaults.standard.string(forKey: "WallpaperEngine.lockScreenWallpaperTitle") ??
            "Abi Toads"

        let desktopStatus = engine.isPlaying ? "🖥️ Desktop: \(desktopTitle)" : "⏸️ Desktop (Paused): \(desktopTitle)"
        let desktopItem = NSMenuItem(title: desktopStatus, action: nil, keyEquivalent: "")
        desktopItem.isEnabled = false
        menu.addItem(desktopItem)

        let lockItem = NSMenuItem(title: "🔒 Lock Screen: \(lockTitle)", action: nil, keyEquivalent: "")
        lockItem.isEnabled = false
        menu.addItem(lockItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Wallpaper Gallery Store (Steam Workshop / Backdrop Hub)
        let galleryItem = NSMenuItem(
            title: "Browse Wallpaper Gallery & Workshop...",
            action: #selector(handleOpenGallery),
            keyEquivalent: "g"
        )
        galleryItem.target = self
        menu.addItem(galleryItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Wallpapers List
        let backdropItems = cachedWallpapers.filter { !$0.isCustom }
        let backdropHeader = NSMenuItem(title: "Downloaded Wallpapers (\(backdropItems.count))", action: nil, keyEquivalent: "")
        backdropHeader.isEnabled = false
        menu.addItem(backdropHeader)

        if backdropItems.isEmpty {
            let emptyItem = NSMenuItem(title: "  (No downloaded wallpapers found)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for item in backdropItems {
                let badge = item.type == .video ? "🎬" : "🖼️"
                let isDesktop = engine.currentDesktopWallpaper?.id == item.id
                let isLock = engine.currentLockScreenWallpaper?.id == item.id ||
                    lockTitle.lowercased().contains(item.title.lowercased())

                var markers: [String] = []
                if isDesktop { markers.append("🖥️ Desktop") }
                if isLock { markers.append("🔒 Lock") }
                let markerSuffix = markers.isEmpty ? "" : "  [\(markers.joined(separator: ", "))]"

                let menuItem = NSMenuItem(
                    title: "\(badge)  \(item.title)\(markerSuffix)",
                    action: #selector(handleSelectDesktopWallpaper(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item

                if isDesktop {
                    menuItem.state = .on
                }

                // Submenu for choosing target
                let sub = NSMenu()
                let miDesktop = NSMenuItem(title: "Set as Desktop Wallpaper", action: #selector(handleSelectDesktopWallpaper(_:)), keyEquivalent: "")
                miDesktop.target = self
                miDesktop.representedObject = item
                sub.addItem(miDesktop)

                let miLock = NSMenuItem(title: "Set as Lock Screen Wallpaper", action: #selector(handleSelectLockScreenWallpaper(_:)), keyEquivalent: "")
                miLock.target = self
                miLock.representedObject = item
                sub.addItem(miLock)

                let miBoth = NSMenuItem(title: "Set as Both (Desktop + Lock Screen)", action: #selector(handleSelectBothWallpapers(_:)), keyEquivalent: "")
                miBoth.target = self
                miBoth.representedObject = item
                sub.addItem(miBoth)

                menuItem.submenu = sub
                menu.addItem(menuItem)
            }
        }

        // Custom items
        let customItems = cachedWallpapers.filter { $0.isCustom }
        if !customItems.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let customHeader = NSMenuItem(title: "Custom Wallpapers", action: nil, keyEquivalent: "")
            customHeader.isEnabled = false
            menu.addItem(customHeader)

            for item in customItems {
                let badge = item.type == .video ? "🎬" : "🖼️"
                let isDesktop = engine.currentDesktopWallpaper?.id == item.id
                let menuItem = NSMenuItem(
                    title: "\(badge)  \(item.title)",
                    action: #selector(handleSelectDesktopWallpaper(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item
                if isDesktop { menuItem.state = .on }

                let sub = NSMenu()
                let miDesktop = NSMenuItem(title: "Set as Desktop", action: #selector(handleSelectDesktopWallpaper(_:)), keyEquivalent: "")
                miDesktop.target = self
                miDesktop.representedObject = item
                sub.addItem(miDesktop)

                let miLock = NSMenuItem(title: "Set as Lock Screen", action: #selector(handleSelectLockScreenWallpaper(_:)), keyEquivalent: "")
                miLock.target = self
                miLock.representedObject = item
                sub.addItem(miLock)

                menuItem.submenu = sub
                menu.addItem(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // 4. Custom File Action
        let addCustomItem = NSMenuItem(
            title: "Choose Custom Video/Image...",
            action: #selector(handleChooseCustomWallpaper),
            keyEquivalent: "o"
        )
        addCustomItem.target = self
        menu.addItem(addCustomItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Playback Controls
        let playPauseItem = NSMenuItem(
            title: engine.isPlaying ? "Pause Wallpaper" : "Resume Wallpaper",
            action: #selector(handleTogglePlayPause),
            keyEquivalent: "p"
        )
        playPauseItem.target = self
        menu.addItem(playPauseItem)

        let muteItem = NSMenuItem(
            title: "Mute Audio",
            action: #selector(handleToggleMute),
            keyEquivalent: "m"
        )
        muteItem.target = self
        muteItem.state = engine.isMuted ? .on : .off
        menu.addItem(muteItem)

        // Submenu: Playback Speed (Time Scale)
        let speedSubmenu = NSMenu()
        let speedOptions: [(title: String, rate: Double)] = [
            ("0.5x (Slow Motion)", 0.5),
            ("0.75x (Relaxed)", 0.75),
            ("1.0x (Normal)", 1.0),
            ("1.25x (Brisk)", 1.25),
            ("1.5x (Fast)", 1.5),
            ("2.0x (Double Speed)", 2.0)
        ]
        let currentRate = engine.currentPlaybackRate
        for opt in speedOptions {
            let item = NSMenuItem(
                title: opt.title,
                action: #selector(handleSelectPlaybackRate(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = opt.rate
            if abs(currentRate - opt.rate) < 0.05 {
                item.state = .on
            }
            speedSubmenu.addItem(item)
        }
        let speedMenuItem = NSMenuItem(title: "Playback Speed (Time Scale)", action: nil, keyEquivalent: "")
        speedMenuItem.submenu = speedSubmenu
        menu.addItem(speedMenuItem)

        // Submenu: Scaling Mode
        let scalingSubmenu = NSMenu()
        for mode in WallpaperScalingMode.allCases {
            let modeItem = NSMenuItem(
                title: mode.rawValue,
                action: #selector(handleSelectScalingMode(_:)),
                keyEquivalent: ""
            )
            modeItem.target = self
            modeItem.representedObject = mode
            modeItem.state = (engine.scalingMode == mode) ? .on : .off
            scalingSubmenu.addItem(modeItem)
        }
        let scalingMenuItem = NSMenuItem(title: "Scaling Mode", action: nil, keyEquivalent: "")
        scalingMenuItem.submenu = scalingSubmenu
        menu.addItem(scalingMenuItem)

        // Submenu: Window Layer
        let layerSubmenu = NSMenu()
        for mode in WindowLayerMode.allCases {
            let layerItem = NSMenuItem(
                title: mode.rawValue,
                action: #selector(handleSelectLayerMode(_:)),
                keyEquivalent: ""
            )
            layerItem.target = self
            layerItem.representedObject = mode
            layerItem.state = (engine.layerMode == mode) ? .on : .off
            layerSubmenu.addItem(layerItem)
        }
        let layerMenuItem = NSMenuItem(title: "Desktop Layer", action: nil, keyEquivalent: "")
        layerMenuItem.submenu = layerSubmenu
        menu.addItem(layerMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Tools & Utilities
        let refreshItem = NSMenuItem(
            title: "Refresh Library",
            action: #selector(handleRefreshLibrary),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openAssetsItem = NSMenuItem(
            title: "Reveal Wallpapers in Finder",
            action: #selector(handleOpenAssetsInFinder),
            keyEquivalent: ""
        )
        openAssetsItem.target = self
        menu.addItem(openAssetsItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Quit
        let quitItem = NSMenuItem(
            title: "Quit Backdrop Player",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func handleOpenGallery() {
        GalleryWindowController.shared.show()
    }

    @objc private func handleSelectDesktopWallpaper(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? WallpaperItem else { return }
        engine.setDesktopWallpaper(item)
    }

    @objc private func handleSelectLockScreenWallpaper(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? WallpaperItem else { return }
        engine.setLockScreenWallpaper(item)
    }

    @objc private func handleSelectBothWallpapers(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? WallpaperItem else { return }
        engine.setBothWallpapers(item)
    }

    @objc private func handleChooseCustomWallpaper() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .movie,
            .quickTimeMovie,
            .mpeg4Movie,
            .image,
            .heic,
            .png,
            .jpeg
        ]
        panel.message = "Choose a video or image to use as wallpaper"

        NSApp.activate(ignoringOtherApps: true)

        if panel.runModal() == .OK, let selectedURL = panel.url {
            if let item = libraryService.addCustomWallpaper(url: selectedURL) {
                loadWallpapers()
                engine.setDesktopWallpaper(item)
            }
        }
    }

    @objc private func handleTogglePlayPause() {
        engine.togglePlayPause()
    }

    @objc private func handleToggleMute() {
        engine.isMuted.toggle()
    }

    @objc private func handleSelectPlaybackRate(_ sender: NSMenuItem) {
        guard let rate = sender.representedObject as? Double else { return }
        engine.setPlaybackRate(rate)
    }

    @objc private func handleSelectScalingMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? WallpaperScalingMode else { return }
        engine.scalingMode = mode
    }

    @objc private func handleSelectLayerMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? WindowLayerMode else { return }
        engine.layerMode = mode
    }

    @objc private func handleRefreshLibrary() {
        loadWallpapers()
    }

    @objc private func handleOpenAssetsInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: libraryService.localWallpapersDirectory.path)
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
