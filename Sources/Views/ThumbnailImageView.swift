import SwiftUI
import AppKit
import AVFoundation

public final class ThumbnailCacheManager {
    public static let shared = ThumbnailCacheManager()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let diskCacheURL: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheURL = caches.appendingPathComponent("BackdropPlayer/Thumbnails")
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        memoryCache.countLimit = 150
    }

    private func cacheKey(for item: CatalogItem) -> String {
        let raw = item.thumbnailURL?.absoluteString ?? item.downloadURL.absoluteString
        return String(format: "%016lx", raw.hashValue)
    }

    public func loadThumbnail(for item: CatalogItem, completion: @escaping (NSImage?) -> Void) {
        let key = cacheKey(for: item)

        // 1. Memory Cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            completion(cached)
            return
        }

        // 2. Disk Cache
        let diskPath = diskCacheURL.appendingPathComponent("\(key).jpg")
        if let diskImage = NSImage(contentsOf: diskPath) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            completion(diskImage)
            return
        }

        // 3. Local file thumbnail (HEIC, JPG, PNG)
        if let thumbURL = item.thumbnailURL, thumbURL.isFileURL {
            if let img = NSImage(contentsOf: thumbURL) {
                saveToDiskAndMemory(img, key: key, diskPath: diskPath)
                completion(img)
                return
            }
        }

        // 4. Remote HTTP Thumbnail (WebP, JPG, PNG)
        if let thumbURL = item.thumbnailURL, thumbURL.scheme?.hasPrefix("http") == true {
            var request = URLRequest(url: thumbURL)
            request.timeoutInterval = 15.0
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self, let data = data, let img = NSImage(data: data) else {
                    // Fallback to video frame extraction if thumbnail download fails
                    self?.extractVideoFrame(item: item, key: key, diskPath: diskPath, completion: completion)
                    return
                }
                self.saveToDiskAndMemory(img, key: key, diskPath: diskPath)
                DispatchQueue.main.async {
                    completion(img)
                }
            }.resume()
            return
        }

        // 5. Extract frame from Video
        extractVideoFrame(item: item, key: key, diskPath: diskPath, completion: completion)
    }

    private func extractVideoFrame(item: CatalogItem, key: String, diskPath: URL, completion: @escaping (NSImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let asset = AVURLAsset(url: item.previewURL ?? item.downloadURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 360)
            let time = CMTime(seconds: 1.0, preferredTimescale: 60)

            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let img = NSImage(cgImage: cgImage, size: NSSize(width: 320, height: 180))
                self.saveToDiskAndMemory(img, key: key, diskPath: diskPath)
                DispatchQueue.main.async {
                    completion(img)
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    private func saveToDiskAndMemory(_ image: NSImage, key: String, diskPath: URL) {
        memoryCache.setObject(image, forKey: key as NSString)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            return
        }
        try? jpegData.write(to: diskPath)
    }
}

public struct ThumbnailImageView: View {
    public let item: CatalogItem
    @State private var thumbnail: NSImage?
    @State private var isLoading: Bool = true

    public init(item: CatalogItem) {
        self.item = item
    }

    public var body: some View {
        ZStack {
            if let img = thumbnail {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 140)
                    .clipped()
            } else if isLoading {
                ZStack {
                    fallbackGradient
                    ProgressView()
                        .scaleEffect(0.7)
                }
                .frame(height: 140)
            } else {
                fallbackGradient
                    .frame(height: 140)
            }
        }
        .frame(height: 140)
        .clipped()
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        ThumbnailCacheManager.shared.loadThumbnail(for: item) { img in
            self.thumbnail = img
            self.isLoading = false
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

    private var iconName: String {
        if item.category.contains("Steam") || item.category.contains("Workshop") { return "flame.fill" }
        if item.category.contains("Space") || item.category.contains("Earth") { return "globe.americas.fill" }
        if item.category.contains("Nature") { return "leaf.fill" }
        if item.category.contains("Gaming") { return "gamecontroller.fill" }
        if item.category.contains("Anime") { return "sparkles" }
        return "play.rectangle.fill"
    }

    private var gradientColors: [Color] {
        if item.category.contains("Steam") { return [Color.orange.opacity(0.85), Color.purple.opacity(0.85)] }
        if item.category.contains("Space") { return [Color.purple.opacity(0.8), Color.blue.opacity(0.8)] }
        if item.category.contains("Nature") { return [Color.green.opacity(0.8), Color.teal.opacity(0.8)] }
        if item.category.contains("Backdrop") { return [Color.indigo.opacity(0.8), Color.pink.opacity(0.8)] }
        return [Color.blue.opacity(0.8), Color.cyan.opacity(0.8)]
    }
}
