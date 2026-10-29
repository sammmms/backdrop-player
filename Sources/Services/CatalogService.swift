import Foundation
import AppKit

public final class CatalogService {
    public static let shared = CatalogService()

    private init() {}

    public func fetchCatalog() -> [CatalogItem] {
        var items: [CatalogItem] = []

        // 1. Discover cached Backdrop assets with REAL on-disk HEIC thumbnails
        items.append(contentsOf: fetchBackdropCachedItems())

        // 2. Curated Anime, Gaming & Lofi community loops with direct image thumbnails & MP4s
        items.append(contentsOf: curatedCommunityItems)

        // 3. Apple Aerial 4K Official Assets (High-Speed Apple CDN)
        items.append(contentsOf: appleAerialItems)

        return items
    }

    private func fetchBackdropCachedItems() -> [CatalogItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let catalogDir = home.appendingPathComponent("Library/Application Support/Backdrop/Catalog")
        let sectionsDir = home.appendingPathComponent("Library/Application Support/Backdrop/DiscoverV3/sections")

        var items: [CatalogItem] = []
        var seenTitles = Set<String>()

        guard let sections = try? FileManager.default.contentsOfDirectory(at: sectionsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        for sURL in sections where sURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: sURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sectionItems = json["items"] as? [[String: Any]] else { continue }

            for item in sectionItems {
                guard let title = item["title"] as? String,
                      !seenTitles.contains(title.lowercased()),
                      let media = item["media"] as? [String: Any] else { continue }

                // Find preview video
                var previewFileURL: URL?
                var candidateVideoIDs: [String] = []
                if let p = media["largePreview"] as? [String: Any], let pid = p["id"] as? String {
                    candidateVideoIDs.append(pid)
                }
                if let p = media["preview"] as? [String: Any], let pid = p["id"] as? String {
                    candidateVideoIDs.append(pid)
                }

                for pid in candidateVideoIDs {
                    let fileURL = catalogDir.appendingPathComponent("\(pid)-preview.mov")
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        previewFileURL = fileURL
                        break
                    }
                }

                // If preview video exists on disk, find its real thumbnail
                if let videoURL = previewFileURL {
                    seenTitles.insert(title.lowercased())

                    var thumbURL: URL?
                    var candidateThumbIDs: [String] = []
                    if let t = media["largeThumbnail"] as? [String: Any], let tid = t["id"] as? String {
                        candidateThumbIDs.append(tid)
                    }
                    if let t = media["thumbnail"] as? [String: Any], let tid = t["id"] as? String {
                        candidateThumbIDs.append(tid)
                    }

                    for tid in candidateThumbIDs {
                        let candidateFile = catalogDir.appendingPathComponent("\(tid).heic")
                        if FileManager.default.fileExists(atPath: candidateFile.path) {
                            thumbURL = candidateFile
                            break
                        }
                    }

                    let rawCategory = (item["category"] as? String ?? "anime").capitalized
                    let size = (try? videoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)

                    items.append(
                        CatalogItem(
                            id: "backdrop-\(videoURL.lastPathComponent)",
                            title: title,
                            category: "Backdrop (\(rawCategory))",
                            thumbnailURL: thumbURL,
                            previewURL: videoURL,
                            downloadURL: videoURL,
                            resolution: "Full HD",
                            fileSizeString: formattedSize,
                            sourceDescription: "Instant Mac Cache",
                            isLocalCopy: true
                        )
                    )
                }
            }
        }

        return items.sorted { $0.title < $1.title }
    }

    private var curatedCommunityItems: [CatalogItem] {
        let cdnBase = "https://raw.githubusercontent.com/adiambassador/wallpapers/main"
        return [
            CatalogItem(
                id: "comm-gojo-blue-eyes",
                title: "Gojo Satoru (Infinite Void)",
                category: "Anime & Gaming",
                thumbnailURL: URL(string: "\(cdnBase)/.previews/jjk/gojo-blue-eyes-jjk.1920x1080.jpg"),
                downloadURL: URL(string: "\(cdnBase)/jjk/gojo-blue-eyes-jjk.1920x1080.mp4")!,
                resolution: "1080p 60fps",
                fileSizeString: "15.4 MB",
                sourceDescription: "Jujutsu Kaisen"
            ),
            CatalogItem(
                id: "comm-gojo-neon-nights",
                title: "Gojo Satoru (Neon Nights)",
                category: "Anime & Gaming",
                thumbnailURL: URL(string: "\(cdnBase)/.previews/jjk/gojo-neon-nights.1920x1080.jpg"),
                downloadURL: URL(string: "\(cdnBase)/jjk/gojo-neon-nights.1920x1080.mp4")!,
                resolution: "1080p 60fps",
                fileSizeString: "18.2 MB",
                sourceDescription: "Jujutsu Kaisen"
            ),
            CatalogItem(
                id: "comm-mahoraga",
                title: "Mahoraga (Wheel of Adaptation)",
                category: "Anime & Gaming",
                thumbnailURL: URL(string: "\(cdnBase)/.previews/jjk/mahoraga-wheel-of-adaptation.1920x1080.jpg"),
                downloadURL: URL(string: "\(cdnBase)/jjk/mahoraga-wheel-of-adaptation.1920x1080.mp4")!,
                resolution: "1080p 60fps",
                fileSizeString: "14.8 MB",
                sourceDescription: "Jujutsu Kaisen"
            ),
            CatalogItem(
                id: "comm-yae-miko-moonlit",
                title: "Yae Miko (Moonlit Shrine)",
                category: "Anime & Gaming",
                thumbnailURL: URL(string: "\(cdnBase)/.previews/genshin/yae-mikos-moonlit.1920x1080.jpg"),
                downloadURL: URL(string: "\(cdnBase)/genshin/yae-mikos-moonlit.1920x1080.mp4")!,
                resolution: "1080p 60fps",
                fileSizeString: "5.2 MB",
                sourceDescription: "Genshin Impact"
            ),
            CatalogItem(
                id: "comm-yae-miko-ambiance",
                title: "Yae Miko (Enchanted Ambiance)",
                category: "Anime & Gaming",
                thumbnailURL: URL(string: "\(cdnBase)/.previews/genshin/yae-mikos-enchanted-ambiance.1920x1080.jpg"),
                downloadURL: URL(string: "\(cdnBase)/genshin/yae-mikos-enchanted-ambiance.1920x1080.mp4")!,
                resolution: "1080p 60fps",
                fileSizeString: "1.5 MB",
                sourceDescription: "Genshin Impact"
            ),
            CatalogItem(
                id: "comm-mizuki-genshin",
                title: "Yumemizuki Mizuki (Aesthetic)",
                category: "Anime & Gaming",
                thumbnailURL: URL(string: "\(cdnBase)/.previews/genshin/yumemizuki-mizuki-genshin-impact.1920x1080.jpg"),
                downloadURL: URL(string: "\(cdnBase)/genshin/yumemizuki-mizuki-genshin-impact.1920x1080.mp4")!,
                resolution: "1080p 60fps",
                fileSizeString: "9.4 MB",
                sourceDescription: "Genshin Impact"
            ),
            CatalogItem(
                id: "comm-tears-of-steel",
                title: "Cyberpunk Lab & Robots",
                category: "Lofi & Aesthetic",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4")!,
                resolution: "1080p 60fps",
                fileSizeString: "35 MB",
                sourceDescription: "Open Sci-Fi"
            )
        ]
    }

    private var appleAerialItems: [CatalogItem] {
        return [
            CatalogItem(
                id: "apple-korea-japan-night",
                title: "Korea & Japan Night from Space",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_GMT026_363A_103NC_E1027_KOREA_JAPAN_NIGHT_v18_SDR_PS_20180907_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "280 MB",
                sourceDescription: "Apple Aerial 4K (ISS)"
            ),
            CatalogItem(
                id: "apple-africa-night",
                title: "Africa Night & Auroras from ISS",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_GMT312_162NC_139M_1041_AFRICA_NIGHT_v14_SDR_FINAL_20180706_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "310 MB",
                sourceDescription: "Apple Aerial 4K (ISS)"
            ),
            CatalogItem(
                id: "apple-seals-underwater",
                title: "Seals Gliding Underwater",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/SE_A016_C009_SDR_20190717_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "190 MB",
                sourceDescription: "Apple Aerial 4K (Underwater)"
            ),
            CatalogItem(
                id: "apple-palau-jellies",
                title: "Golden Jellyfish Lake (Palau)",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/PA_A001_C007_SDR_20190717_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "220 MB",
                sourceDescription: "Apple Aerial 4K (Underwater)"
            ),
            CatalogItem(
                id: "apple-greenland-glaciers",
                title: "Greenland Icebergs & Glaciers",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_GL_G002_C002_PSNK_v03_SDR_PS_20180925_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "260 MB",
                sourceDescription: "Apple Aerial 4K (Drone)"
            ),
            CatalogItem(
                id: "apple-london-aerial",
                title: "London Skyline Dusk Aerial",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_L007_C007_PS_v01_SDR_PS_20180925_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "270 MB",
                sourceDescription: "Apple Aerial 4K (Helicopter)"
            ),
            CatalogItem(
                id: "apple-los-angeles",
                title: "Los Angeles Twilight Freeway",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_LA_A008_C004_ALTB_ED_FROM_FLAME_RETIME_v46_SDR_PS_20180917_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "245 MB",
                sourceDescription: "Apple Aerial 4K (City)"
            ),
            CatalogItem(
                id: "apple-china-wall",
                title: "Great Wall of China & Terraces",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_CH_C002_C005_PSNK_v05_SDR_PS_FINAL_20180709_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "290 MB",
                sourceDescription: "Apple Aerial 4K (Landscape)"
            ),
            CatalogItem(
                id: "apple-sahara-italy",
                title: "Sahara to Mediterranean Orbit",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_A009_C001_010181A_v09_SDR_PS_FINAL_20180725_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "230 MB",
                sourceDescription: "Apple Aerial 4K (Satellite)"
            )
        ]
    }
}
