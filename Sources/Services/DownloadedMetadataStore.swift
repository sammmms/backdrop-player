import Foundation

public struct DownloadedMetadata: Codable {
    public let id: String
    public let title: String
    public let category: String
    public let resolution: String
    public let sourceDescription: String

    public init(id: String, title: String, category: String, resolution: String, sourceDescription: String) {
        self.id = id
        self.title = title
        self.category = category
        self.resolution = resolution
        self.sourceDescription = sourceDescription
    }
}

public final class DownloadedMetadataStore {
    public static let shared = DownloadedMetadataStore()

    private let fileURL: URL
    private var cache: [String: DownloadedMetadata] = [:]
    private let queue = DispatchQueue(label: "com.backdropplayer.metadata", attributes: .concurrent)

    private static let defaultMetadata: [String: DownloadedMetadata] = [
        "kirby floating on pond": DownloadedMetadata(
            id: "kirby-pond",
            title: "Kirby Floating on Pond",
            category: "Gaming",
            resolution: "Full HD 60fps",
            sourceDescription: "Wallpaper Engine Space"
        ),
        "dark blind queen": DownloadedMetadata(
            id: "dark-blind-queen",
            title: "Dark Blind Queen",
            category: "Fantasy & Abstract",
            resolution: "4K UHD",
            sourceDescription: "DesktopHut (4K PC)"
        ),
        "cute animal pond relax live wallpaper": DownloadedMetadata(
            id: "cute-animal-pond",
            title: "Cute Animal Pond Relax Live Wallpaper",
            category: "Nature & Space",
            resolution: "4K UHD",
            sourceDescription: "DesktopHut (4K PC)"
        ),
        "bambi- forest cottage": DownloadedMetadata(
            id: "bambi-cottage",
            title: "Bambi: Forest Cottage",
            category: "Nature & Space",
            resolution: "Full HD",
            sourceDescription: "DesktopHut"
        ),
        "bambi: forest cottage": DownloadedMetadata(
            id: "bambi-cottage",
            title: "Bambi: Forest Cottage",
            category: "Nature & Space",
            resolution: "Full HD",
            sourceDescription: "DesktopHut"
        ),
        "the sift": DownloadedMetadata(
            id: "the-sift",
            title: "The Sift",
            category: "Sci-Fi & Cyberpunk",
            resolution: "Full HD",
            sourceDescription: "DesktopHut"
        ),
        "cloud watching frogs": DownloadedMetadata(
            id: "cloud-frogs",
            title: "Cloud Watching Frogs",
            category: "Nature & Space",
            resolution: "Full HD",
            sourceDescription: "DesktopHut"
        ),
        "lonely cat audio visualizer (night sky)": DownloadedMetadata(
            id: "lonely-cat",
            title: "Lonely Cat Audio Visualizer (Night Sky)",
            category: "Lofi & Aesthetic",
            resolution: "1080p 60fps",
            sourceDescription: "Wallpaper Engine Space"
        ),
        "blossom tree through a roof": DownloadedMetadata(
            id: "blossom-tree",
            title: "Blossom Tree Through a Roof",
            category: "Nature & Space",
            resolution: "4K UHD",
            sourceDescription: "Wallpaper Engine Space"
        ),
        "cyberpunk- edgerunner-lucy[4k]": DownloadedMetadata(
            id: "cyberpunk-lucy",
            title: "Cyberpunk: Edgerunner-Lucy[4K]",
            category: "Sci-Fi & Cyberpunk",
            resolution: "4K UHD",
            sourceDescription: "DesktopHut (4K PC)"
        ),
        "cyberpunk: edgerunner-lucy[4k]": DownloadedMetadata(
            id: "cyberpunk-lucy",
            title: "Cyberpunk: Edgerunner-Lucy[4K]",
            category: "Sci-Fi & Cyberpunk",
            resolution: "4K UHD",
            sourceDescription: "DesktopHut (4K PC)"
        )
    ]

    private init() {
        let dir = BackdropLibraryService.shared.localWallpapersDirectory
        self.fileURL = dir.appendingPathComponent(".metadata.json")
        load()
    }

    private func normalizedKey(_ title: String) -> String {
        return title
            .replacingOccurrences(of: ":", with: "-")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() {
        cache = Self.defaultMetadata
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: DownloadedMetadata].self, from: data) else {
            return
        }
        for (k, v) in dict {
            cache[normalizedKey(k)] = v
        }
    }

    public func get(title: String) -> DownloadedMetadata? {
        queue.sync {
            let key = normalizedKey(title)
            if let direct = cache[key] {
                return direct
            }
            // Check title without colons / hyphens
            let cleanKey = key.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
            return cache.first(where: {
                $0.key.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces) == cleanKey
            })?.value
        }
    }

    public func save(item: CatalogItem) {
        queue.async(flags: .barrier) {
            let key = self.normalizedKey(item.title)
            let meta = DownloadedMetadata(
                id: item.id,
                title: item.title,
                category: item.category,
                resolution: item.resolution,
                sourceDescription: item.sourceDescription
            )
            self.cache[key] = meta
            if let data = try? JSONEncoder().encode(self.cache) {
                try? data.write(to: self.fileURL)
            }
        }
    }

    public func remove(title: String) {
        queue.async(flags: .barrier) {
            let key = self.normalizedKey(title)
            self.cache.removeValue(forKey: key)
            if let data = try? JSONEncoder().encode(self.cache) {
                try? data.write(to: self.fileURL)
            }
        }
    }
}
