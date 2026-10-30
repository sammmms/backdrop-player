import AppKit
import AVFoundation
import AVKit

public enum WindowLayerMode: String, CaseIterable {
    case desktop = "Desktop Layer (Recommended)"
    case belowIcons = "Below Desktop Icons"

    public var windowLevel: NSWindow.Level {
        switch self {
        case .desktop:
            // Sits directly above system desktop wallpaper and any existing wallpaper renderer
            return NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 2)
        case .belowIcons:
            return NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        }
    }
}

public enum WallpaperScalingMode: String, CaseIterable {
    case aspectFill = "Fill Screen (Crop)"
    case aspectFit = "Fit Screen (Letterbox)"

    public var avGravity: AVLayerVideoGravity {
        switch self {
        case .aspectFill:
            return .resizeAspectFill
        case .aspectFit:
            return .resizeAspect
        }
    }
}

public final class WallpaperEngine: NSObject {
    public static let shared = WallpaperEngine()

    public var currentWallpaper: WallpaperItem? {
        return currentDesktopWallpaper
    }
    public private(set) var currentDesktopWallpaper: WallpaperItem?
    public private(set) var currentLockScreenWallpaper: WallpaperItem?
    public private(set) var isPlaying: Bool = true

    public var isMuted: Bool {
        get { UserDefaults.standard.object(forKey: "WallpaperEngine.isMuted") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "WallpaperEngine.isMuted")
            updateAudioState()
        }
    }

    public var layerMode: WindowLayerMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "WallpaperEngine.layerMode") ?? ""
            return WindowLayerMode(rawValue: raw) ?? .desktop
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "WallpaperEngine.layerMode")
            updateWindowLevels()
        }
    }

    public var scalingMode: WallpaperScalingMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "WallpaperEngine.scalingMode") ?? ""
            return WallpaperScalingMode(rawValue: raw) ?? .aspectFill
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "WallpaperEngine.scalingMode")
            updateScalingMode()
        }
    }

    public var onStateChange: (() -> Void)?

    public func notifyStateChange() {
        NotificationCenter.default.post(name: NSNotification.Name("WallpaperEngineStateChanged"), object: nil)
        onStateChange?()
    }

    private final class ScreenSession {
        let screen: NSScreen
        let window: WallpaperWindow
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var playerView: AVPlayerView?
        var imageView: NSImageView?

        init(screen: NSScreen, window: WallpaperWindow) {
            self.screen = screen
            self.window = window
        }
    }

    private var sessions: [ScreenSession] = []
    private var isSystemSleeping: Bool = false

    private override init() {
        super.init()
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(handleScreensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        wsCenter.addObserver(
            self,
            selector: #selector(handleScreensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    @objc private func handleScreenLocked() {
        print("[WallpaperEngine] Screen locked, pausing playback to preserve CPU...")
        isSystemSleeping = true
        pauseInternal()
    }

    @objc private func handleScreenUnlocked() {
        print("[WallpaperEngine] Screen unlocked, resuming playback...")
        isSystemSleeping = false
        if isPlaying {
            resumeInternal()
        }
    }

    @objc private func handleScreenParametersChanged() {
        print("[WallpaperEngine] Screen configuration changed, rebuilding display windows...")
        reloadCurrentWallpaper()
    }

    @objc private func handleScreensDidSleep() {
        print("[WallpaperEngine] Screens went to sleep, pausing playback...")
        isSystemSleeping = true
        pauseInternal()
    }

    @objc private func handleScreensDidWake() {
        print("[WallpaperEngine] Screens woke up, resuming playback...")
        isSystemSleeping = false
        if isPlaying {
            resumeInternal()
        }
    }

    // MARK: - Playback & Wallpaper Control

    public enum WallpaperSyncTarget {
        case desktop
        case lockScreen
        case both
    }

    private let syncQueue = DispatchQueue(label: "com.backdrop.wallpaperSyncQueue", qos: .userInitiated)

    public func setDesktopWallpaper(_ item: WallpaperItem, completion: ((Bool) -> Void)? = nil) {
        print("[WallpaperEngine] Setting Desktop wallpaper: \(item.title) (\(item.fileURL.lastPathComponent))")
        self.currentDesktopWallpaper = item
        self.isPlaying = true

        UserDefaults.standard.set(item.fileURL.path, forKey: "WallpaperEngine.desktopWallpaperPath")
        UserDefaults.standard.set(item.id, forKey: "WallpaperEngine.desktopWallpaperId")
        UserDefaults.standard.set(item.title, forKey: "WallpaperEngine.desktopWallpaperTitle")

        // Smoothly reuse existing windows or create new ones for new screens without destroying windows
        var activeSessions: [ScreenSession] = []
        let currentScreens = NSScreen.screens

        for screen in currentScreens {
            if let existing = sessions.first(where: { $0.screen == screen || $0.screen.frame == screen.frame }) {
                updateSessionContent(session: existing, item: item)
                activeSessions.append(existing)
            } else {
                let session = createSession(for: screen, item: item)
                activeSessions.append(session)
            }
        }

        // Clean up removed screens (e.g. external display disconnected)
        for oldSession in sessions {
            if !currentScreens.contains(where: { $0 == oldSession.screen || $0.frame == oldSession.screen.frame }) {
                oldSession.player?.pause()
                oldSession.player?.removeAllItems()
                oldSession.imageView?.animates = false
                oldSession.window.orderOut(nil)
            }
        }

        self.sessions = activeSessions
        print("[WallpaperEngine] Active desktop sessions: \(sessions.count)")
        notifyStateChange()

        // Sync native macOS Desktop & Mission Control spaces bar in background
        syncQueue.async { [weak self] in
            let success = self?.syncNativeStore(for: item, target: .desktop) ?? false
            DispatchQueue.main.async {
                completion?(success)
            }
        }
    }

    public func setLockScreenWallpaper(_ item: WallpaperItem, completion: ((Bool) -> Void)? = nil) {
        print("[WallpaperEngine] Setting Lock Screen wallpaper: \(item.title)")
        self.currentLockScreenWallpaper = item
        UserDefaults.standard.set(item.fileURL.path, forKey: "WallpaperEngine.lockScreenWallpaperPath")
        UserDefaults.standard.set(item.id, forKey: "WallpaperEngine.lockScreenWallpaperId")
        UserDefaults.standard.set(item.title, forKey: "WallpaperEngine.lockScreenWallpaperTitle")

        syncQueue.async { [weak self] in
            let success = self?.syncNativeStore(for: item, target: .lockScreen) ?? false
            DispatchQueue.main.async {
                self?.notifyStateChange()
                completion?(success)
            }
        }
    }

    public func setBothWallpapers(_ item: WallpaperItem, completion: ((Bool) -> Void)? = nil) {
        print("[WallpaperEngine] Setting Both Desktop & Lock Screen wallpapers: \(item.title)")
        self.currentDesktopWallpaper = item
        self.currentLockScreenWallpaper = item
        self.isPlaying = true

        UserDefaults.standard.set(item.fileURL.path, forKey: "WallpaperEngine.desktopWallpaperPath")
        UserDefaults.standard.set(item.id, forKey: "WallpaperEngine.desktopWallpaperId")
        UserDefaults.standard.set(item.title, forKey: "WallpaperEngine.desktopWallpaperTitle")

        UserDefaults.standard.set(item.fileURL.path, forKey: "WallpaperEngine.lockScreenWallpaperPath")
        UserDefaults.standard.set(item.id, forKey: "WallpaperEngine.lockScreenWallpaperId")
        UserDefaults.standard.set(item.title, forKey: "WallpaperEngine.lockScreenWallpaperTitle")

        var activeSessions: [ScreenSession] = []
        let currentScreens = NSScreen.screens

        for screen in currentScreens {
            if let existing = sessions.first(where: { $0.screen == screen || $0.screen.frame == screen.frame }) {
                updateSessionContent(session: existing, item: item)
                activeSessions.append(existing)
            } else {
                let session = createSession(for: screen, item: item)
                activeSessions.append(session)
            }
        }

        for oldSession in sessions {
            if !currentScreens.contains(where: { $0 == oldSession.screen || $0.frame == oldSession.screen.frame }) {
                oldSession.player?.pause()
                oldSession.player?.removeAllItems()
                oldSession.imageView?.animates = false
                oldSession.window.orderOut(nil)
            }
        }

        self.sessions = activeSessions
        print("[WallpaperEngine] Active desktop sessions: \(sessions.count)")
        notifyStateChange()

        syncQueue.async { [weak self] in
            let success = self?.syncNativeStore(for: item, target: .both) ?? false
            DispatchQueue.main.async {
                self?.notifyStateChange()
                completion?(success)
            }
        }
    }

    public func setWallpaper(_ item: WallpaperItem) {
        setDesktopWallpaper(item)
    }

    // MARK: - Native Wallpaper Store Synchronization (Spaces, Mission Control & Lock Screen)

    public func syncLockScreen(for item: WallpaperItem) {
        setLockScreenWallpaper(item)
    }

    private func ensureStillFrame(for item: WallpaperItem) -> URL? {
        let stillsDir = BackdropLibraryService.shared.localWallpapersDirectory.appendingPathComponent(".stills")
        try? FileManager.default.createDirectory(at: stillsDir, withIntermediateDirectories: true)
        let safeTitle = item.title.replacingOccurrences(of: "/", with: "-")
        let stillURL = stillsDir.appendingPathComponent("\(safeTitle).jpg")

        if FileManager.default.fileExists(atPath: stillURL.path) {
            return stillURL
        }

        let projectStills = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/GitHub/backdrop-player/wallpapers/.stills/\(safeTitle).jpg")
        if FileManager.default.fileExists(atPath: projectStills.path) {
            try? FileManager.default.copyItem(at: projectStills, to: stillURL)
            return stillURL
        }

        if item.type == .image, let image = NSImage(contentsOf: item.fileURL) {
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
                    try? data.write(to: stillURL)
                    return stillURL
                }
            }
        }

        if item.type == .video {
            let asset = AVURLAsset(url: item.fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 60)
            let time = CMTime(seconds: 1.0, preferredTimescale: 60)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
                    try? data.write(to: stillURL)
                    return stillURL
                }
            }
        }

        return nil
    }

    @discardableResult
    private func syncNativeStore(for item: WallpaperItem, target: WallpaperSyncTarget) -> Bool {
        guard let stillURL = ensureStillFrame(for: item) else {
            print("[WallpaperEngine] Failed to generate still frame for \(item.title)")
            return false
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

        guard var plist = NSDictionary(contentsOf: indexURL) as? [String: Any] else {
            print("[WallpaperEngine] Could not read Index.plist")
            return false
        }

        let shouldUpdateDesktop = (target == .desktop || target == .both)
        let shouldUpdateIdle = (target == .lockScreen || target == .both)

        let innerPayload: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": stillURL.absoluteString]
        ]

        guard let confData = try? PropertyListSerialization.data(fromPropertyList: innerPayload, format: .binary, options: 0) else {
            print("[WallpaperEngine] Failed to create binary property list data")
            return false
        }

        func updateChoice(dict: inout [String: Any], key: String) {
            guard var section = dict[key] as? [String: Any],
                  var content = section["Content"] as? [String: Any],
                  var choices = content["Choices"] as? [[String: Any]] else {
                return
            }

            for i in 0..<choices.count {
                choices[i]["Provider"] = "com.apple.wallpaper.choice.image"
                choices[i]["Configuration"] = confData
            }

            content["Choices"] = choices
            section["Content"] = content
            dict[key] = section
        }

        func traverseAndUpdate(dict: inout [String: Any]) {
            if shouldUpdateDesktop && dict["Desktop"] != nil {
                updateChoice(dict: &dict, key: "Desktop")
            }
            if shouldUpdateIdle && dict["Idle"] != nil {
                updateChoice(dict: &dict, key: "Idle")
            }

            for (k, v) in dict {
                if var sub = v as? [String: Any] {
                    traverseAndUpdate(dict: &sub)
                    dict[k] = sub
                }
            }
        }

        traverseAndUpdate(dict: &plist)

        guard let outData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            print("[WallpaperEngine] Failed to serialize Index.plist to XML")
            return false
        }

        do {
            try outData.write(to: indexURL, options: .atomic)

            // Notify WallpaperAgent to immediately reload Index.plist and update Spaces thumbnails
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            p.arguments = ["WallpaperAgent"]
            try p.run()
            p.waitUntilExit()

            // Also update NSWorkspace desktopImageURL for all active screens if desktop was targeted
            if shouldUpdateDesktop {
                DispatchQueue.main.async {
                    for screen in NSScreen.screens {
                        try? NSWorkspace.shared.setDesktopImageURL(stillURL, for: screen, options: [:])
                    }
                }
            }

            print("[WallpaperEngine] Successfully synced native macOS wallpaper (\(target)) with: \(stillURL.lastPathComponent)")
            return true
        } catch {
            print("[WallpaperEngine] Error writing Index.plist: \(error)")
            return false
        }
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    public func pause() {
        isPlaying = false
        pauseInternal()
        notifyStateChange()
    }

    public func resume() {
        isPlaying = true
        if !isSystemSleeping {
            resumeInternal()
        }
        notifyStateChange()
    }

    private func pauseInternal() {
        for session in sessions {
            session.player?.pause()
        }
    }

    private func resumeInternal() {
        for session in sessions {
            session.player?.play()
        }
    }

    public func reloadCurrentWallpaper() {
        guard let current = currentWallpaper else { return }
        setWallpaper(current)
    }

    // MARK: - Session Setup

    private func createSession(for screen: NSScreen, item: WallpaperItem) -> ScreenSession {
        let window = WallpaperWindow(screen: screen, level: layerMode.windowLevel)
        let session = ScreenSession(screen: screen, window: window)

        if item.type == .video {
            let asset = AVURLAsset(url: item.fileURL)
            let playerItem = AVPlayerItem(asset: asset)
            let queuePlayer = AVQueuePlayer(playerItem: playerItem)
            queuePlayer.isMuted = isMuted

            let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

            let playerView = AVPlayerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            playerView.player = queuePlayer
            playerView.controlsStyle = .none
            playerView.videoGravity = scalingMode.avGravity
            playerView.autoresizingMask = [.width, .height]

            window.contentView = playerView

            session.player = queuePlayer
            session.looper = looper
            session.playerView = playerView

            if isPlaying && !isSystemSleeping {
                queuePlayer.play()
                print("[WallpaperEngine] Started queuePlayer playback on \(screen.localizedName), isMuted=\(isMuted)")
            }
        } else {
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            imageView.image = NSImage(contentsOf: item.fileURL)
            imageView.animates = true
            imageView.imageScaling = (scalingMode == .aspectFill) ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width, .height]
            window.contentView = imageView
            session.imageView = imageView
        }

        window.orderFrontRegardless()
        return session
    }

    private func updateSessionContent(session: ScreenSession, item: WallpaperItem) {
        // 1. Clean up existing media safely
        session.player?.pause()
        session.player?.removeAllItems()
        session.looper = nil
        session.player = nil
        session.playerView = nil
        session.imageView?.animates = false
        session.imageView?.image = nil
        session.imageView = nil

        // 2. Setup new media on the existing persistent window
        if item.type == .video {
            let asset = AVURLAsset(url: item.fileURL)
            let playerItem = AVPlayerItem(asset: asset)
            let queuePlayer = AVQueuePlayer(playerItem: playerItem)
            queuePlayer.isMuted = isMuted

            let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

            let playerView = AVPlayerView(frame: NSRect(origin: .zero, size: session.screen.frame.size))
            playerView.player = queuePlayer
            playerView.controlsStyle = .none
            playerView.videoGravity = scalingMode.avGravity
            playerView.autoresizingMask = [.width, .height]

            session.window.contentView = playerView

            session.player = queuePlayer
            session.looper = looper
            session.playerView = playerView

            if isPlaying && !isSystemSleeping {
                queuePlayer.play()
                print("[WallpaperEngine] Swapped video playback on \(session.screen.localizedName) to: \(item.title)")
            }
        } else {
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: session.screen.frame.size))
            imageView.image = NSImage(contentsOf: item.fileURL)
            imageView.animates = true
            imageView.imageScaling = (scalingMode == .aspectFill) ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width, .height]
            session.window.contentView = imageView
            session.imageView = imageView
            print("[WallpaperEngine] Swapped image display on \(session.screen.localizedName) to: \(item.title)")
        }

        session.window.orderFrontRegardless()
    }

    private func teardownSessions() {
        for session in sessions {
            session.player?.pause()
            session.player?.removeAllItems()
            session.looper = nil
            session.player = nil
            session.playerView = nil
            session.imageView?.animates = false
            session.imageView?.image = nil
            session.imageView = nil
            session.window.orderOut(nil)
        }
        sessions.removeAll()
    }

    private func updateAudioState() {
        for session in sessions {
            session.player?.isMuted = isMuted
        }
        notifyStateChange()
    }

    private func updateWindowLevels() {
        let newLevel = layerMode.windowLevel
        for session in sessions {
            session.window.level = newLevel
            session.window.orderFrontRegardless()
        }
        notifyStateChange()
    }

    private func updateScalingMode() {
        let gravity = scalingMode.avGravity
        for session in sessions {
            session.playerView?.videoGravity = gravity
            session.imageView?.imageScaling = (scalingMode == .aspectFill) ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        }
        notifyStateChange()
    }
}
