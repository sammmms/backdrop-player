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

    private struct ScreenSession {
        let screen: NSScreen
        let window: WallpaperWindow
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var playerView: AVPlayerView?
        var imageView: NSImageView?
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

    public func setDesktopWallpaper(_ item: WallpaperItem) {
        print("[WallpaperEngine] Setting Desktop wallpaper: \(item.title) (\(item.fileURL.lastPathComponent))")
        self.currentDesktopWallpaper = item
        self.isPlaying = true

        UserDefaults.standard.set(item.fileURL.path, forKey: "WallpaperEngine.desktopWallpaperPath")
        UserDefaults.standard.set(item.id, forKey: "WallpaperEngine.desktopWallpaperId")
        UserDefaults.standard.set(item.title, forKey: "WallpaperEngine.desktopWallpaperTitle")

        teardownSessions()

        for screen in NSScreen.screens {
            let session = createSession(for: screen, item: item)
            sessions.append(session)
        }

        print("[WallpaperEngine] Active desktop sessions: \(sessions.count)")
        notifyStateChange()
    }

    public func setLockScreenWallpaper(_ item: WallpaperItem, completion: ((Bool) -> Void)? = nil) {
        print("[WallpaperEngine] Setting Lock Screen wallpaper: \(item.title)")
        self.currentLockScreenWallpaper = item
        UserDefaults.standard.set(item.fileURL.path, forKey: "WallpaperEngine.lockScreenWallpaperPath")
        UserDefaults.standard.set(item.id, forKey: "WallpaperEngine.lockScreenWallpaperId")
        UserDefaults.standard.set(item.title, forKey: "WallpaperEngine.lockScreenWallpaperTitle")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.updateLockScreenOnly(for: item) ?? false
            DispatchQueue.main.async {
                self?.notifyStateChange()
                completion?(success)
            }
        }
    }

    public func setBothWallpapers(_ item: WallpaperItem) {
        setDesktopWallpaper(item)
        setLockScreenWallpaper(item)
    }

    public func setWallpaper(_ item: WallpaperItem) {
        setDesktopWallpaper(item)
    }

    // MARK: - Lock Screen Synchronization (Independent)

    public func syncLockScreen(for item: WallpaperItem) {
        setLockScreenWallpaper(item)
    }

    private func updateLockScreenOnly(for item: WallpaperItem) -> Bool {
        let stillsDir = BackdropLibraryService.shared.localWallpapersDirectory.appendingPathComponent(".stills")
        try? FileManager.default.createDirectory(at: stillsDir, withIntermediateDirectories: true)
        let safeTitle = item.title.replacingOccurrences(of: "/", with: "-")
        let stillURL = stillsDir.appendingPathComponent("\(safeTitle).jpg")

        if !FileManager.default.fileExists(atPath: stillURL.path) {
            if item.type == .video {
                let asset = AVURLAsset(url: item.fileURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 1.0, preferredTimescale: 60)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    let rep = NSBitmapImageRep(cgImage: cgImage)
                    if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) {
                        try? data.write(to: stillURL)
                    }
                }
            } else if let image = NSImage(contentsOf: item.fileURL) {
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
                    try? data?.write(to: stillURL)
                }
            }
        }

        guard FileManager.default.fileExists(atPath: stillURL.path) else {
            print("[WallpaperEngine] Failed to generate still frame for lock screen")
            return false
        }

        // Update macOS Store/Index.plist Idle dictionary ONLY so Desktop is untouched
        let home = FileManager.default.homeDirectoryForCurrentUser
        let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

        guard var plist = NSDictionary(contentsOf: indexURL) as? [String: Any] else {
            print("[WallpaperEngine] Could not read Index.plist")
            return false
        }

        func updateIdleOnly(_ dict: inout [String: Any]) {
            for (k, v) in dict {
                if k == "Idle", var idle = v as? [String: Any] {
                    if var content = idle["Content"] as? [String: Any],
                       var choices = content["Choices"] as? [[String: Any]] {
                        for i in 0..<choices.count {
                            let inner: [String: Any] = [
                                "type": "imageFile",
                                "url": ["relative": stillURL.absoluteString]
                            ]
                            if let conf = try? PropertyListSerialization.data(fromPropertyList: inner, format: .binary, options: 0) {
                                choices[i]["Provider"] = "com.apple.wallpaper.choice.image"
                                choices[i]["Configuration"] = conf
                            }
                        }
                        content["Choices"] = choices
                        idle["Content"] = content
                        dict["Idle"] = idle
                    }
                } else if var sub = v as? [String: Any] {
                    updateIdleOnly(&sub)
                    dict[k] = sub
                }
            }
        }

        updateIdleOnly(&plist)

        if let outData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? outData.write(to: indexURL)

            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            p.arguments = ["WallpaperAgent"]
            try? p.run()
            print("[WallpaperEngine] Successfully set Lock Screen to: \(item.title) (\(stillURL.lastPathComponent))")
            return true
        }

        return false
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
        var session = ScreenSession(screen: screen, window: window)

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
            imageView.imageScaling = (scalingMode == .aspectFill) ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width, .height]
            window.contentView = imageView
            session.imageView = imageView
        }

        window.orderFrontRegardless()
        return session
    }

    private func teardownSessions() {
        for session in sessions {
            session.player?.pause()
            session.window.contentView = nil
            session.window.close()
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
