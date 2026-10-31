import Foundation
import AppKit

public final class CatalogService {
    public static let shared = CatalogService()

    public static let availableMarketplaces: [String] = [
        "🌐 All Marketplaces",
        "🔥 Steam Workshop",
        "🌸 MoeWalls (Anime & Aesthetic)",
        "⚡ DesktopHut (4K PC)",
        "🪐 Wallpaper Engine Space",
        "🍏 Apple Aerials 4K",
        "🎬 Backdrop Collection",
        "💾 Downloaded / Ready",
        "🔗 Custom Video URL"
    ]

    public static let availableCategories: [String] = [
        "All Categories",
        "Anime & Manga",
        "Gaming",
        "Sci-Fi & Cyberpunk",
        "Nature & Space",
        "Lofi & Aesthetic",
        "Cars & Vehicles",
        "Fantasy & Abstract"
    ]

    private init() {}

    public func fetchCatalog() -> [CatalogItem] {
        var items: [CatalogItem] = []
        items.append(contentsOf: localFeaturedItems)
        items.append(contentsOf: steamWallpaperEngineItems)
        items.append(contentsOf: fetchBackdropCachedItems())
        items.append(contentsOf: curatedCommunityItems)
        items.append(contentsOf: appleAerialItems)
        return items
    }

    // MARK: - Multi-Marketplace Live Search & Filter

    public func searchLive(
        query: String,
        marketplace: String = "🌐 All Marketplaces",
        category: String = "All Categories",
        page: Int = 1
    ) async -> [CatalogItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch marketplace {
        case "🔥 Steam Workshop":
            let steamQuery = trimmedQuery.isEmpty
                ? (category == "All Categories" ? "" : categorySteamKeyword(for: category))
                : trimmedQuery
            return await SteamWorkshopBackendService.shared.search(query: steamQuery, sort: "trend", page: page)

        case "🌸 MoeWalls (Anime & Aesthetic)":
            return await MoeWallsBackendService.shared.search(query: trimmedQuery, category: category, page: page)

        case "⚡ DesktopHut (4K PC)":
            return await DesktopHutBackendService.shared.search(query: trimmedQuery, category: category, page: page)

        case "🪐 Wallpaper Engine Space":
            guard page == 1 else { return [] }
            var list = steamWallpaperEngineItems
            if !trimmedQuery.isEmpty {
                list = list.filter {
                    $0.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                    $0.category.localizedCaseInsensitiveContains(trimmedQuery)
                }
            }
            if category != "All Categories" {
                list = filterByCategory(items: list, category: category)
            }
            return list

        case "🍏 Apple Aerials 4K":
            guard page == 1 else { return [] }
            var list = appleAerialItems
            if !trimmedQuery.isEmpty {
                list = list.filter {
                    $0.title.localizedCaseInsensitiveContains(trimmedQuery) ||
                    $0.sourceDescription.localizedCaseInsensitiveContains(trimmedQuery)
                }
            }
            return list

        case "🎬 Backdrop Collection":
            guard page == 1 else { return [] }
            var list = localFeaturedItems + fetchBackdropCachedItems()
            if !trimmedQuery.isEmpty {
                list = list.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
            }
            if category != "All Categories" {
                list = filterByCategory(items: list, category: category)
            }
            return list

        case "💾 Downloaded / Ready":
            guard page == 1 else { return [] }
            let dir = BackdropLibraryService.shared.localWallpapersDirectory
            let localFiles = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            var list = fetchCatalog().filter { item in
                localFiles.contains(where: { $0.lowercased().contains(item.title.lowercased()) }) || item.isLocalCopy
            }
            if !trimmedQuery.isEmpty {
                list = list.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
            }
            return list

        case "🔗 Custom Video URL":
            return []

        default:
            // "🌐 All Marketplaces" (Aggregate across providers with Infinite Pagination!)
            return await aggregateAllMarketplaces(query: trimmedQuery, category: category, page: page)
        }
    }

    // Backward-compatible overload
    public func searchLive(query: String, category: String = "All") async -> [CatalogItem] {
        return await searchLive(query: query, marketplace: "🌐 All Marketplaces", category: category, page: 1)
    }

    private func aggregateAllMarketplaces(query: String, category: String, page: Int = 1) async -> [CatalogItem] {
        async let steamTask = SteamWorkshopBackendService.shared.search(
            query: query.isEmpty ? (category == "All Categories" ? "" : categorySteamKeyword(for: category)) : query,
            sort: "trend",
            page: page
        )
        async let moeTask = MoeWallsBackendService.shared.search(query: query, category: category, page: page)
        async let dhTask = DesktopHutBackendService.shared.search(query: query, category: category, page: page)

        let (steam, moe, dh) = await (steamTask, moeTask, dhTask)

        var merged: [CatalogItem] = []
        var seen = Set<String>()

        // Interleave top live online results across providers
        let maxCount = max(steam.count, max(moe.count, dh.count))
        for i in 0..<maxCount {
            if i < steam.count {
                let it = steam[i]
                if !seen.contains(it.title.lowercased()) {
                    seen.insert(it.title.lowercased())
                    merged.append(it)
                }
            }
            if i < moe.count {
                let it = moe[i]
                if !seen.contains(it.title.lowercased()) {
                    seen.insert(it.title.lowercased())
                    merged.append(it)
                }
            }
            if i < dh.count {
                let it = dh[i]
                if !seen.contains(it.title.lowercased()) {
                    seen.insert(it.title.lowercased())
                    merged.append(it)
                }
            }
        }

        // If user searched for a specific keyword on page 1, also check if curated open catalog items match
        if page == 1 && !query.isEmpty {
            let onlineExtra = (steamWallpaperEngineItems + appleAerialItems).filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.category.localizedCaseInsensitiveContains(query)
            }
            for it in onlineExtra where !seen.contains(it.title.lowercased()) {
                seen.insert(it.title.lowercased())
                merged.append(it)
            }
        }

        return merged
    }

    private func categorySteamKeyword(for category: String) -> String {
        switch category {
        case "Anime & Manga": return "anime"
        case "Gaming": return "game"
        case "Sci-Fi & Cyberpunk": return "cyberpunk"
        case "Nature & Space": return "nature"
        case "Lofi & Aesthetic": return "lofi"
        case "Cars & Vehicles": return "car"
        case "Fantasy & Abstract": return "fantasy"
        default: return ""
        }
    }

    private func filterByCategory(items: [CatalogItem], category: String) -> [CatalogItem] {
        let kw = categorySteamKeyword(for: category)
        return items.filter {
            $0.category.localizedCaseInsensitiveContains(kw) ||
            $0.title.localizedCaseInsensitiveContains(kw)
        }
    }

    // MARK: - Featured Clean Local Wallpapers

    public var localFeaturedItems: [CatalogItem] {
        let localDir = BackdropLibraryService.shared.localWallpapersDirectory
        let stillsDir = localDir.appendingPathComponent(".stills")

        let defs: [(title: String, file: String, still: String, res: String, size: String, cat: String)] = [
            ("Kirby Floating on Pond", "Kirby Floating on Pond.mov", "Kirby Floating on Pond.heic", "Full HD", "37 MB", "Backdrop Collection"),
            ("Abi Toads (Original)", "Abi Toads.mov", "Abi Toads.heic", "Full HD", "46 MB", "Backdrop Collection"),
            ("Dancing Petals", "Dancing Petals.mov", "Dancing Petals.heic", "Full HD", "42 MB", "Backdrop Collection"),
            ("Room in the Forest", "Room in the forest.mov", "Room in the forest.heic", "Full HD", "34 MB", "Backdrop Collection")
        ]

        return defs.compactMap { def in
            let videoURL = localDir.appendingPathComponent(def.file)
            let stillURL = stillsDir.appendingPathComponent(def.still)

            guard FileManager.default.fileExists(atPath: videoURL.path) else { return nil }
            let thumb = FileManager.default.fileExists(atPath: stillURL.path) ? stillURL : nil

            return CatalogItem(
                id: "feat-\(def.title)",
                title: def.title,
                category: def.cat,
                thumbnailURL: thumb,
                previewURL: videoURL,
                downloadURL: videoURL,
                resolution: def.res,
                fileSizeString: def.size,
                sourceDescription: "Pre-installed Asset",
                isLocalCopy: true
            )
        }
    }

    // MARK: - Steam / Wallpaper Engine Space Items (4K/60fps)

    public var steamWallpaperEngineItems: [CatalogItem] {
        let baseVideo = "https://media.wallpaperengine.space/wallpapers/v1"
        let basePoster = "https://media.wallpaperengine.space/posters/v1"

        let list: [(slug: String, title: String, cat: String, res: String, size: String, source: String)] = [
            ("blossom-tree-through-a-roof", "Blossom Tree Through a Roof", "Nature & Space", "4K UHD", "2.2 MB", "Wallpaper Engine Space"),
            ("white-porsche-gt3-rs-cherry-blossoms", "White Porsche GT3 RS (Cherry Blossoms)", "Cars & Vehicles", "4K 60fps", "6.8 MB", "Wallpaper Engine Space"),
            ("elaina-window-day-night-wandering-witch", "Elaina Window Day & Night (Wandering Witch)", "Anime & Manga", "1080p 60fps", "14.2 MB", "Wallpaper Engine Space"),
            ("frieren-snowy-eye-tracking", "Frieren in Falling Snow (Eye Tracking)", "Anime & Manga", "4K UHD", "18.5 MB", "Wallpaper Engine Space"),
            ("blade-runner-2049", "Blade Runner 2049 (Cyberpunk City)", "Sci-Fi & Cyberpunk", "4K UHD", "12.0 MB", "Wallpaper Engine Space"),
            ("atri-sunflower-meadow-my-dear-moments", "Atri Sunflower Meadow (My Dear Moments)", "Anime & Manga", "1080p 60fps", "8.4 MB", "Wallpaper Engine Space"),
            ("lonely-cat-audio-visualizer", "Lonely Cat Audio Visualizer (Night Sky)", "Lofi & Aesthetic", "1080p 60fps", "5.1 MB", "Wallpaper Engine Space"),
            ("hatsune-miku-star-eyes-colorful", "Hatsune Miku (Star Eyes Colorful)", "Anime & Manga", "4K 60fps", "16.7 MB", "Wallpaper Engine Space"),
            ("winter-night-northern-lights", "Winter Night Northern Lights (Auroras)", "Nature & Space", "4K UHD", "9.3 MB", "Wallpaper Engine Space"),
            ("sunlit-overgrown-arches", "Sunlit Overgrown Arches", "Nature & Space", "4K UHD", "7.8 MB", "Wallpaper Engine Space"),
            ("yellow-flowers-in-the-wind", "Yellow Flowers in the Wind", "Nature & Space", "1080p 60fps", "4.5 MB", "Wallpaper Engine Space"),
            ("petals-of-the-moon", "Petals of the Moon", "Fantasy & Abstract", "4K UHD", "11.2 MB", "Wallpaper Engine Space"),
            ("ice-princess-frozen-cathedral-wlop", "Ice Princess Frozen Cathedral (WLOP)", "Fantasy & Abstract", "4K 60fps", "15.0 MB", "Wallpaper Engine Space"),
            ("sakura-tree", "Sakura Tree Blooming (Falling Petals)", "Nature & Space", "1080p 60fps", "6.2 MB", "Wallpaper Engine Space"),
            ("cozy-room", "Cozy Lofi Bedroom (Rain Outside)", "Lofi & Aesthetic", "1080p 60fps", "4.8 MB", "Wallpaper Engine Space"),
            ("rainy-night", "Rainy Night Cityscape (Neon Reflections)", "Sci-Fi & Cyberpunk", "1080p 60fps", "5.4 MB", "Wallpaper Engine Space")
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
                        let f = catalogDir.appendingPathComponent("\(tid)-thumbnail.heic")
                        if FileManager.default.fileExists(atPath: f.path) {
                            thumbURL = f
                            break
                        }
                    }

                    let size = (try? videoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let mb = Double(size) / (1024 * 1024)

                    items.append(
                        CatalogItem(
                            id: "cache-\(title)",
                            title: title,
                            category: "Backdrop Collection",
                            thumbnailURL: thumbURL,
                            previewURL: videoURL,
                            downloadURL: videoURL,
                            resolution: "1080p MOV",
                            fileSizeString: String(format: "%.1f MB", mb),
                            sourceDescription: "Backdrop Cache",
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
                category: "Anime & Manga",
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
                category: "Anime & Manga",
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
                category: "Anime & Manga",
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
                category: "Gaming",
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
                category: "Gaming",
                thumbnailURL: URL(string: "\(cdnBase)/.previews/genshin/yae-mikos-enchanted-ambiance.1920x1080.jpg"),
                previewURL: URL(string: "\(cdnBase)/genshin/yae-mikos-enchanted-ambiance.1920x1080.mp4"),
                downloadURL: URL(string: "\(cdnBase)/genshin/yae-mikos-enchanted-ambiance.1920x1080.mp4")!,
                resolution: "1080p 60fps",
                fileSizeString: "1.5 MB",
                sourceDescription: "Genshin Impact"
            )
        ]
    }

    // MARK: - Official Apple Aerial 4K Streams

    public var appleAerialItems: [CatalogItem] {
        return [
            CatalogItem(
                id: "apple-aurora-borealis",
                title: "Aurora Borealis & Australis Orbit",
                category: "Nature & Space",
                thumbnailURL: nil,
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/DB_D011_C010_CR_HDR_HEVC.mov"),
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/DB_D011_C010_CR_HDR_HEVC.mov")!,
                resolution: "4K HDR",
                fileSizeString: "280 MB",
                sourceDescription: "Apple Aerial 4K (Space)"
            ),
            CatalogItem(
                id: "apple-iss-africa-night",
                title: "ISS Crossing Africa at Night",
                category: "Nature & Space",
                thumbnailURL: nil,
                previewURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_A001_C005_AFRICA_NIGHT_v14_SDR_FINAL_20180706_SDR_4K_HEVC.mov"),
                downloadURL: URL(string: "https://sylvan.apple.com/Aerials/2x/Videos/comp_A001_C005_AFRICA_NIGHT_v14_SDR_FINAL_20180706_SDR_4K_HEVC.mov")!,
                resolution: "4K Ultra HD",
                fileSizeString: "310 MB",
                sourceDescription: "Apple Aerial 4K (ISS)"
            ),
            CatalogItem(
                id: "apple-seals-underwater",
                title: "Seals Gliding Underwater",
                category: "Nature & Space",
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
                category: "Nature & Space",
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
                category: "Nature & Space",
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
                category: "Nature & Space",
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
                category: "Cars & Vehicles",
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
                category: "Nature & Space",
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
                category: "Nature & Space",
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
