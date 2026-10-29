import SwiftUI
import AppKit
import AVFoundation

public struct ThumbnailImageView: View {
    public let item: CatalogItem
    @State private var localImage: NSImage?
    @State private var isLoadingLocal: Bool = false

    public init(item: CatalogItem) {
        self.item = item
    }

    public var body: some View {
        ZStack {
            if let localImg = localImage {
                Image(nsImage: localImg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let thumbURL = item.thumbnailURL, thumbURL.scheme?.hasPrefix("http") == true {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        fallbackGradient
                    case .empty:
                        ZStack {
                            fallbackGradient
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    @unknown default:
                        fallbackGradient
                    }
                }
            } else {
                fallbackGradient
            }
        }
        .frame(height: 140)
        .clipped()
        .onAppear {
            loadLocalThumbnailIfNeeded()
        }
    }

    private var fallbackGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: gradientColors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: iconName)
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.8))
        )
    }

    private func loadLocalThumbnailIfNeeded() {
        if let thumbURL = item.thumbnailURL, thumbURL.isFileURL {
            if let img = NSImage(contentsOf: thumbURL) {
                self.localImage = img
                return
            }
        }

        // If it's a local video (Backdrop preview), extract frame
        if item.downloadURL.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: item.downloadURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 1.0, preferredTimescale: 60)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    let img = NSImage(cgImage: cgImage, size: NSSize(width: 320, height: 180))
                    DispatchQueue.main.async {
                        self.localImage = img
                    }
                }
            }
        }
    }

    private var iconName: String {
        if item.category.contains("Space") || item.category.contains("Earth") { return "globe.americas.fill" }
        if item.category.contains("Nature") { return "leaf.fill" }
        if item.category.contains("Gaming") { return "gamecontroller.fill" }
        if item.category.contains("Anime") { return "sparkles" }
        return "play.rectangle.fill"
    }

    private var gradientColors: [Color] {
        if item.category.contains("Space") { return [Color.purple.opacity(0.8), Color.blue.opacity(0.8)] }
        if item.category.contains("Nature") { return [Color.green.opacity(0.8), Color.teal.opacity(0.8)] }
        if item.category.contains("Backdrop") { return [Color.indigo.opacity(0.8), Color.pink.opacity(0.8)] }
        return [Color.blue.opacity(0.8), Color.cyan.opacity(0.8)]
    }
}
