import Foundation
import AppKit

public final class CatalogService {
    public static let shared = CatalogService()

    private init() {}

    public func fetchCatalog() -> [CatalogItem] {
        var items: [CatalogItem] = []

        // 1. Featured Local Unencrypted Wallpapers (Instant playback)
        items.append(contentsOf: localFeaturedItems)

        // 2. Steam / Wallpaper Engine Space Open Catalog (Direct 4K/1080p MP4 loops + WebP posters)
        items.append(contentsOf: steamWallpaperEngineItems)

        // 3. Backdrop Cached Items (44 on-disk HEIC thumbnails & MOV previews)
        items.append(contentsOf: fetchBackdropCachedItems())

        // 4. Curated Anime, Gaming & Lofi community loops
        items.append(contentsOf: curatedCommunityItems)

        // 5. Apple Aerial 4K Official Cinematic Collection
        items.append(contentsOf: appleAerialItems)

        return items
    }

    // MARK: - Featured Clean Local Wallpapers

    public var localFeaturedItems: [CatalogItem] {
        let localDir = BackdropLibraryService.shared.localWallpapersDirectory
        let stillsDir = localDir.appendingPathComponent(".stills")

        let defs: [(title: String, file: String, still: String, res: String, size: String, cat: String)] = [
            ("Abi Toads (Rainy Day)", "Abi Toads.mov", "Abi Toads.jpg", "4K 60fps", "138 MB", "Backdrop Collection"),
            ("Kirby Floating on Pond", "Kirby Floating on Pond.mov", "Kirby Floating on Pond.jpg", "1080p 60fps", "12.7 MB", "Anime & Gaming"),
            ("Dancing Petals", "Dancing Petals.mov", "Dancing Petals.jpg", "1080p 60fps", "10.1 MB", "Lofi & Aesthetic"),
            ("Room in the forest", "Room in the forest.mov", "Room in the forest.jpg", "4K 60fps", "136 MB", "Lofi & Aesthetic")
        ]

        var items: [CatalogItem] = []
        for d in defs {
            let videoURL = localDir.appendingPathComponent(d.file)
            guard FileManager.default.fileExists(atPath: videoURL.path) else { continue }

            let stillURL = stillsDir.appendingPathComponent(d.still)
            let thumb = FileManager.default.fileExists(atPath: stillURL.path) ? stillURL : videoURL

            items.append(
                CatalogItem(
                    id: "local-\(d.title)",
                    title: d.title,
                    category: d.cat,
                    thumbnailURL: thumb,
                    previewURL: videoURL,
                    downloadURL: videoURL,
                    resolution: d.res,
                    fileSizeString: d.size,
                    sourceDescription: "Ready on Mac",
                    isLocalCopy: true
                )
            )
        }
        return items
    }

    // MARK: - Steam / Wallpaper Engine Space Open Catalog

    public var steamWallpaperEngineItems: [CatalogItem] {
        let baseVideo = "https://media.wallpaperengine.space/wallpapers/v1"
        let basePoster = "https://media.wallpaperengine.space/posters/v1"

        let list: [(slug: String, title: String, cat: String, res: String, size: String, source: String)] = [
            ("blossom-tree-through-a-roof", "Blossom Tree Through a Roof", "Steam / Wallpaper Engine", "4K UHD", "2.2 MB", "Wallpaper Engine Space"),
            ("white-porsche-gt3-rs-cherry-blossoms", "White Porsche GT3 RS (Cherry Blossoms)", "Steam / Wallpaper Engine", "4K 60fps", "6.8 MB", "Wallpaper Engine Space"),
            ("elaina-window-day-night-wandering-witch", "Elaina Window Day & Night (Wandering Witch)", "Steam / Wallpaper Engine", "1080p 60fps", "14.2 MB", "Wallpaper Engine Space"),
            ("frieren-snowy-eye-tracking", "Frieren in Falling Snow (Eye Tracking)", "Steam / Wallpaper Engine", "4K UHD", "18.5 MB", "Wallpaper Engine Space"),
            ("blade-runner-2049", "Blade Runner 2049 (Cyberpunk City)", "Steam / Wallpaper Engine", "4K UHD", "12.0 MB", "Wallpaper Engine Space"),
            ("atri-sunflower-meadow-my-dear-moments", "Atri Sunflower Meadow (My Dear Moments)", "Steam / Wallpaper Engine", "1080p 60fps", "8.4 MB", "Wallpaper Engine Space"),
            ("lonely-cat-audio-visualizer", "Lonely Cat Audio Visualizer (Night Sky)", "Steam / Wallpaper Engine", "1080p 60fps", "5.1 MB", "Wallpaper Engine Space"),
            ("hatsune-miku-star-eyes-colorful", "Hatsune Miku (Star Eyes Colorful)", "Steam / Wallpaper Engine", "4K 60fps", "16.7 MB", "Wallpaper Engine Space"),
            ("winter-night-northern-lights", "Winter Night Northern Lights (Auroras)", "Steam / Wallpaper Engine", "4K UHD", "9.3 MB", "Wallpaper Engine Space"),
            ("sunlit-overgrown-arches", "Sunlit Overgrown Arches", "Steam / Wallpaper Engine", "4K UHD", "7.8 MB", "Wallpaper Engine Space"),
            ("yellow-flowers-in-the-wind", "Yellow Flowers in the Wind", "Steam / Wallpaper Engine", "1080p 60fps", "4.5 MB", "Wallpaper Engine Space"),
            ("petals-of-the-moon", "Petals of the Moon", "Steam / Wallpaper Engine", "4K UHD", "11.2 MB", "Wallpaper Engine Space"),
            ("ice-princess-frozen-cathedral-wlop", "Ice Princess Frozen Cathedral (WLOP)", "Steam / Wallpaper Engine", "4K 60fps", "15.0 MB", "Wallpaper Engine Space"),
            ("sakura-tree", "Sakura Tree Blooming (Falling Petals)", "Steam / Wallpaper Engine", "1080p 60fps", "6.2 MB", "Wallpaper Engine Space"),
            ("cozy-room", "Cozy Lofi Bedroom (Rain Outside)", "Steam / Wallpaper Engine", "1080p 60fps", "4.8 MB", "Wallpaper Engine Space"),
            ("rainy-night", "Rainy Night Cityscape (Neon Reflections)", "Steam / Wallpaper Engine", "1080p 60fps", "5.4 MB", "Wallpaper Engine Space")
        ]

        return list.map { item in
            CatalogItem(
                id: "we-\(item.slug)",
                title: item.title,
                category: item.cat,
                thumbnailURL: URL(string: "\(basePoster)/\(item.slug).webp"),
                previewURL: URL(string: "\(baseVideo)/\(item.slug).mp4"),
                downloadURL: URL(string: "\(baseVideo)/\(item.slug).mp4")!,
                resolution: item.res,
                fileSizeString: item.size,
                sourceDescription: item.source,
                isLocalCopy: false
            )
        }
    }

    // MARK: - Backdrop Mac Cache (44 Items)

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
                            sourceDescription: "Mac Cache",
                            isLocalCopy: true
                        )
                    )
                }
            }
        }

        return items.sorted { $0.title < $1.title }
    }

    // MARK: - Curated Anime & Community

    private var curatedCommunityItems: [CatalogItem] {
        let cdnBase = "https://raw.githubusercontent.com/adiambassador/wallpapers/main"
        return [
            CatalogItem(
                id: "comm-gojo-blue-eyes",
                title: "Gojo Satoru (Infinite Void)",
                category: "Anime & Gaming",
                thumbnailURL: URL(string: "\(cdnBase)/.previews/jjk/gojo-blue-eyes-jjk.1920x1080.jpg"),
                previewURL: URL(string: "\(cdnBase)/jjk/gojo-blue-eyes-jjk.1920x1080.mp4"),
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
                previewURL: URL(string: "\(cdnBase)/jjk/gojo-neon-nights.1920x1080.mp4"),
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
                previewURL: URL(string: "\(cdnBase)/jjk/mahoraga-wheel-of-adaptation.1920x1080.mp4"),
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
                previewURL: URL(string: "\(cdnBase)/genshin/yae-mikos-moonlit.1920x1080.mp4"),
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
                previewURL: URL(string: "\(cdnBase)/genshin/yae-mikos-enchanted-ambiance.1920x1080.mp4"),
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
                previewURL: URL(string: "\(cdnBase)/genshin/yumemizuki-mizuki-genshin-impact.1920x1080.mp4"),
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
                previewURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4"),
                downloadURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4")!,
                resolution: "1080p 60fps",
                fileSizeString: "35 MB",
                sourceDescription: "Open Sci-Fi"
            )
        ]
    }

    // MARK: - Apple Aerial 4K Collection

    private var appleAerialItems: [CatalogItem] {
        return [
            CatalogItem(
                id: "apple-korea-japan-night",
                title: "Korea & Japan Night from Space",
                category: "4K Nature & Space",
                thumbnailURL: nil,
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_GMT026_363A_103NC_E1027_KOREA_JAPAN_NIGHT_v18_SDR_PS_20180907_SDR_4K_HEVC.mov"),
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
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_GMT312_162NC_139M_1041_AFRICA_NIGHT_v14_SDR_FINAL_20180706_SDR_4K_HEVC.mov"),
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
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/SE_A016_C009_SDR_20190717_SDR_4K_HEVC.mov"),
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
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/PA_A001_C007_SDR_20190717_SDR_4K_HEVC.mov"),
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
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_GL_G002_C002_PSNK_v03_SDR_PS_20180925_SDR_4K_HEVC.mov"),
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
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_L007_C007_PS_v01_SDR_PS_20180925_SDR_4K_HEVC.mov"),
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
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_LA_A008_C004_ALTB_ED_FROM_FLAME_RETIME_v46_SDR_PS_20180917_SDR_4K_HEVC.mov"),
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
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_CH_C002_C005_PSNK_v05_SDR_PS_FINAL_20180709_SDR_4K_HEVC.mov"),
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
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_A009_C001_010181A_v09_SDR_PS_FINAL_20180725_SDR_4K_HEVC.mov"),
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_A009_C001_010181A_v09_SDR_PS_FINAL_20180725_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "230 MB",
                sourceDescription: "Apple Aerial 4K (Satellite)"
            )
        ]
    }
}
