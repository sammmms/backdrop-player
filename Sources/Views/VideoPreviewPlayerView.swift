import SwiftUI
import AppKit
import AVFoundation
import AVKit

public struct VideoPreviewPlayerView: NSViewRepresentable {
    public let url: URL
    public let rate: Double
    public let isPlaying: Bool
    public let isMuted: Bool

    public init(url: URL, rate: Double = 1.0, isPlaying: Bool = true, isMuted: Bool = true) {
        self.url = url
        self.rate = rate
        self.isPlaying = isPlaying
        self.isMuted = isMuted
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspectFill
        playerView.showsFrameSteppingButtons = false
        playerView.showsSharingServiceButton = false
        playerView.showsFullScreenToggleButton = false

        context.coordinator.setupPlayer(for: url, rate: rate, isPlaying: isPlaying, isMuted: isMuted, in: playerView)
        return playerView
    }

    public func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.update(url: url, rate: rate, isPlaying: isPlaying, isMuted: isMuted, in: nsView)
    }

    public class Coordinator {
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var currentURL: URL?

        func setupPlayer(for url: URL, rate: Double, isPlaying: Bool, isMuted: Bool, in playerView: AVPlayerView) {
            currentURL = url
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let player = AVQueuePlayer(playerItem: item)
            player.isMuted = isMuted

            looper = AVPlayerLooper(player: player, templateItem: item)
            queuePlayer = player
            playerView.player = player

            if isPlaying {
                player.play()
                player.rate = Float(rate)
            } else {
                player.pause()
            }
        }

        func update(url: URL, rate: Double, isPlaying: Bool, isMuted: Bool, in playerView: AVPlayerView) {
            if currentURL != url {
                setupPlayer(for: url, rate: rate, isPlaying: isPlaying, isMuted: isMuted, in: playerView)
                return
            }

            guard let player = queuePlayer else { return }
            player.isMuted = isMuted

            if isPlaying {
                if player.timeControlStatus != .playing {
                    player.play()
                }
                player.rate = Float(rate)
            } else {
                player.pause()
            }
        }
    }
}
