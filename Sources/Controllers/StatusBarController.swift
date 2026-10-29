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

        libraryService.startWatching { [weak self] in
            DispatchQueue.main.async {
                print("[StatusBarController] Detected Backdrop folder changes, refreshing...")
                self?.loadWallpapers()
            }
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
        for item in cachedWallpapers {
            print("  - [\(item.type.rawValue)] \(item.title) (\(item.id)) -> \(item.fileURL.path)")
        }
        rebuildMenu()

        // If no wallpaper is active yet, try restoring last used or pick the first
        if engine.currentWallpaper == nil {
            let lastPath = UserDefaults.standard.string(forKey: "WallpaperEngine.lastWallpaperPath")
            let lastId = UserDefaults.standard.string(forKey: "WallpaperEngine.lastWallpaperId")

            if let matched = cachedWallpapers.first(where: { $0.id == lastId || $0.fileURL.path == lastPath }) {
                print("[StatusBarController] Restoring previously active wallpaper: \(matched.title)")
                engine.setWallpaper(matched)
            } else if let first = cachedWallpapers.first {
                print("[StatusBarController] Auto-selecting first available wallpaper: \(first.title)")
                engine.setWallpaper(first)
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

        if let current = engine.currentWallpaper {
            let statusText = engine.isPlaying
                ? "🟢 Playing: \(current.title)"
                : "⏸️ Paused: \(current.title)"
            let statusMenuItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
            statusMenuItem.isEnabled = false
            menu.addItem(statusMenuItem)
        } else {
            let statusMenuItem = NSMenuItem(title: "⚪ No wallpaper selected", action: nil, keyEquivalent: "")
            statusMenuItem.isEnabled = false
            menu.addItem(statusMenuItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Wallpaper Gallery Store
        let galleryItem = NSMenuItem(
            title: "Browse Wallpaper Gallery...",
            action: #selector(handleOpenGallery),
            keyEquivalent: "g"
        )
        galleryItem.target = self
        menu.addItem(galleryItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Backdrop Wallpapers List
        let backdropItems = cachedWallpapers.filter { !$0.isCustom }
        let backdropHeader = NSMenuItem(title: "Backdrop Library (\(backdropItems.count))", action: nil, keyEquivalent: "")
        backdropHeader.isEnabled = false
        menu.addItem(backdropHeader)

        if backdropItems.isEmpty {
            let emptyItem = NSMenuItem(title: "  (No downloaded wallpapers found)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for item in backdropItems {
                let badge = item.type == .video ? "🎬" : "🖼️"
                let menuItem = NSMenuItem(
                    title: "\(badge)  \(item.title) (\(item.formattedSize))",
                    action: #selector(handleSelectWallpaper(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item

                if engine.currentWallpaper?.id == item.id {
                    menuItem.state = .on
                }
                menu.addItem(menuItem)
            }
        }

        // 3. Custom Wallpapers List
        let customItems = cachedWallpapers.filter { $0.isCustom }
        if !customItems.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let customHeader = NSMenuItem(title: "Custom Wallpapers", action: nil, keyEquivalent: "")
            customHeader.isEnabled = false
            menu.addItem(customHeader)

            for item in customItems {
                let badge = item.type == .video ? "🎬" : "🖼️"
                let menuItem = NSMenuItem(
                    title: "\(badge)  \(item.title)",
                    action: #selector(handleSelectWallpaper(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = item

                if engine.currentWallpaper?.id == item.id {
                    menuItem.state = .on
                }
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
            title: "Refresh Backdrop Library",
            action: #selector(handleRefreshLibrary),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openAssetsItem = NSMenuItem(
            title: "Reveal Assets in Finder",
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

    @objc private func handleSelectWallpaper(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? WallpaperItem else { return }
        engine.setWallpaper(item)
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

        // Temporarily bring app to front for file dialog
        NSApp.activate(ignoringOtherApps: true)

        if panel.runModal() == .OK, let selectedURL = panel.url {
            if let item = libraryService.addCustomWallpaper(url: selectedURL) {
                loadWallpapers()
                engine.setWallpaper(item)
            }
        }
    }

    @objc private func handleTogglePlayPause() {
        engine.togglePlayPause()
    }

    @objc private func handleToggleMute() {
        engine.isMuted.toggle()
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
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: libraryService.defaultAssetsDirectory.path)
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
