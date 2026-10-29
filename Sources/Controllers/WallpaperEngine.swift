import AppKit
import AVFoundation

public enum WindowLayerMode: String, CaseIterable {
    case behindIcons = "Behind Desktop Icons"
    case desktopBase = "Desktop Base Layer"

    public var windowLevel: NSWindow.Level {
        switch self {
        case .behindIcons:
            return NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        case .desktopBase:
            return NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
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

final class PlayerView: NSView {
    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
    }

    override func makeBackingLayer() -> CALayer {
        let l = AVPlayerLayer()
        l.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        return l
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
            return WindowLayerMode(rawValue: raw) ?? .behindIcons
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
        var playerView: PlayerView?
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
        self.currentWallpaper = item
        self.isPlaying = true

        UserDefaults.standard.set(item.fileURL.path, forKey: "WallpaperEngine.lastWallpaperPath")
        UserDefaults.standard.set(item.id, forKey: "WallpaperEngine.lastWallpaperId")

        teardownSessions()

        for screen in NSScreen.screens {
            let session = createSession(for: screen, item: item)
            sessions.append(session)
        }

        onStateChange?()
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

            let playerView = PlayerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            playerView.playerLayer.player = queuePlayer
            playerView.playerLayer.videoGravity = scalingMode.avGravity

            window.contentView = playerView

            session.player = queuePlayer
            session.looper = looper
            session.playerView = playerView

            if isPlaying && !isSystemSleeping {
                queuePlayer.play()
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
            session.playerView?.playerLayer.videoGravity = gravity
            session.imageView?.imageScaling = (scalingMode == .aspectFill) ? .scaleAxesIndependently : .scaleProportionallyUpOrDown
        }
        onStateChange?()
    }
}
