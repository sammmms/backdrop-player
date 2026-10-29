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

    public private(set) var currentWallpaper: WallpaperItem?
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

    // MARK: - Playback Control

    public func setWallpaper(_ item: WallpaperItem) {
        print("[WallpaperEngine] Setting wallpaper: \(item.title) (\(item.fileURL.lastPathComponent))")
        self.currentWallpaper = item
        self.isPlaying = true

        UserDefaults.standard.set(item.fileURL.path, forKey: "WallpaperEngine.lastWallpaperPath")
        UserDefaults.standard.set(item.id, forKey: "WallpaperEngine.lastWallpaperId")

        teardownSessions()

        for screen in NSScreen.screens {
            let session = createSession(for: screen, item: item)
            sessions.append(session)
        }

        print("[WallpaperEngine] Active sessions: \(sessions.count)")
        syncLockScreen(for: item)
        onStateChange?()
    }

    // MARK: - Lock Screen Synchronization

    public func syncLockScreen(for item: WallpaperItem) {
        DispatchQueue.global(qos: .utility).async {
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

            guard FileManager.default.fileExists(atPath: stillURL.path) else { return }

            DispatchQueue.main.async {
                for screen in NSScreen.screens {
                    try? NSWorkspace.shared.setDesktopImageURL(stillURL, for: screen, options: [:])
                }
            }

            // Update macOS Store/Index.plist for Lock Screen & Screen Saver
            let home = FileManager.default.homeDirectoryForCurrentUser
            let indexURL = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

            if var plist = NSDictionary(contentsOf: indexURL) as? [String: Any] {
                func updateChoices(_ dict: inout [String: Any]) {
                    for (k, v) in dict {
                        if var sub = v as? [String: Any] {
                            updateChoices(&sub)
                            dict[k] = sub
                        } else if var arr = v as? [[String: Any]] {
                            for i in 0..<arr.count {
                                let inner: [String: Any] = [
                                    "type": "imageFile",
                                    "url": ["relative": stillURL.absoluteString]
                                ]
                                if let conf = try? PropertyListSerialization.data(fromPropertyList: inner, format: .binary, options: 0) {
                                    arr[i]["Provider"] = "com.apple.wallpaper.choice.image"
                                    arr[i]["Configuration"] = conf
                                }
                            }
                            dict[k] = arr
                        }
                    }
                }

                func copyDesktopToIdle(_ dict: inout [String: Any]) {
                    if let desktop = dict["Desktop"] as? [String: Any], let desktopContent = desktop["Content"] {
                        if var idle = dict["Idle"] as? [String: Any] {
                            idle["Content"] = desktopContent
                            dict["Idle"] = idle
                        }
                    }
                    for (k, v) in dict {
                        if var sub = v as? [String: Any] {
                            copyDesktopToIdle(&sub)
                            dict[k] = sub
                        }
                    }
                }

                updateChoices(&plist)
                copyDesktopToIdle(&plist)

                if let outData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                    try? outData.write(to: indexURL)

                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
                    p.arguments = ["WallpaperAgent"]
                    try? p.run()
                    print("[WallpaperEngine] Synchronized Lock Screen wallpaper to: \(item.title)")
                }
            }
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
        onStateChange?()
    }

    public func resume() {
        isPlaying = true
        if !isSystemSleeping {
            resumeInternal()
        }
        onStateChange?()
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
        onStateChange?()
    }

    private func updateWindowLevels() {
        let newLevel = layerMode.windowLevel
        for session in sessions {
            session.window.level = newLevel
            session.window.orderFrontRegardless()
        }
        onStateChange?()
    }

    private func updateScalingMode() {
        let gravity = scalingMode.avGravity
        for session in sessions {
            session.playerView?.videoGravity = gravity
            session.imageView?.imageScaling = (scalingMode == .aspectFill) ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        }
        onStateChange?()
    }
}
