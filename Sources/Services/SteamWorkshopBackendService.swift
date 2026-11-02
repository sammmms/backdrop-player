import Foundation

public final class SteamWorkshopBackendService {
    public static let shared = SteamWorkshopBackendService()

    private init() {}

    public func search(query: String, sort: String = "trend", page: Int = 1) async -> [CatalogItem] {
        var components = URLComponents(string: "https://steamcommunity.com/workshop/browse/")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "appid", value: "431960"),
            URLQueryItem(name: "section", value: "readytouseitems")
        ]

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "searchtext", value: trimmedQuery))
            queryItems.append(URLQueryItem(name: "browsesort", value: "textsearch"))
        } else {
            queryItems.append(URLQueryItem(name: "browsesort", value: sort))
        }

        if page > 1 {
            queryItems.append(URLQueryItem(name: "p", value: String(page)))
        }

        components.queryItems = queryItems
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15.0

        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        let html = String(decoding: data, as: UTF8.self)

        guard let start = html.range(of: "id=\"valve-ssr-data\"") else { return [] }
        let sub = html[start.upperBound...]
        guard let tagEnd = sub.range(of: ">"),
              let closeScript = sub.range(of: "</script>") else { return [] }

        let jsonStr = String(sub[tagEnd.upperBound..<closeScript.lowerBound])
        guard let jsonData = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let renderContext = obj["renderContext"] as? [String: Any],
              let queryDataStr = renderContext["queryData"] as? String,
              let qData = queryDataStr.data(using: .utf8),
              let queryObj = try? JSONSerialization.jsonObject(with: qData) as? [String: Any],
              let queries = queryObj["queries"] as? [[String: Any]] else { return [] }

        for q in queries {
            if let state = q["state"] as? [String: Any],
               let d = state["data"] as? [String: Any],
               let results = d["results"] as? [[String: Any]], !results.isEmpty {
                return parseResults(results, query: trimmedQuery)
            }
        }
        return []
    }

    private func parseResults(_ results: [[String: Any]], query: String) -> [CatalogItem] {
        var items: [CatalogItem] = []
        for r in results {
            guard let id = r["publishedfileid"] as? String ?? (r["publishedfileid"] as? Int).map(String.init),
                  let title = r["title"] as? String,
                  !title.isEmpty,
                  let preview = r["preview_url"] as? String,
                  let previewURL = URL(string: preview) else { continue }

            let tagsList = (r["tags"] as? [[String: Any]])?.compactMap { $0["tag"] as? String } ?? []

            // 1. Dynamic Resolution Extraction from Steam tags & title
            var resolution = "1080p FHD"
            let lowerTitle = title.lowercased()

            if tagsList.contains(where: { $0.contains("3840 x 2160") || $0.contains("4K") }) ||
               lowerTitle.contains("4k") || lowerTitle.contains("3840") || lowerTitle.contains("2160") {
                resolution = "4K UHD"
            } else if tagsList.contains(where: { $0.contains("2560 x 1440") || $0.contains("1440p") || $0.contains("2K") }) ||
                      lowerTitle.contains("2k") || lowerTitle.contains("1440") {
                resolution = "2K QHD"
            } else if tagsList.contains(where: { $0.contains("3440 x 1440") || $0.lowercased().contains("ultrawide") }) ||
                      lowerTitle.contains("ultrawide") {
                resolution = "Ultrawide 2K"
            } else if tagsList.contains(where: { $0.contains("1920 x 1080") || $0.contains("1080p") }) ||
                      lowerTitle.contains("1080") {
                resolution = "1080p FHD"
            } else if tagsList.contains(where: { $0.contains("720p") }) || lowerTitle.contains("720") {
                resolution = "720p HD"
            }

            if lowerTitle.contains("60fps") || tagsList.contains(where: { $0.lowercased().contains("60fps") }) {
                resolution += " 60fps"
            } else if tagsList.contains("Video") {
                resolution += " Video"
            } else if tagsList.contains("Scene") {
                resolution += " Scene"
            }

            // 2. Real File Size in MB (fallback to subscriptions count)
            var fileSizeStr = ""
            if let fsStr = r["file_size"] as? String, let bytes = Int64(fsStr), bytes > 0 {
                let mb = Double(bytes) / (1024.0 * 1024.0)
                fileSizeStr = String(format: "%.1f MB", mb)
            } else if let bytes = r["file_size"] as? Int64, bytes > 0 {
                let mb = Double(bytes) / (1024.0 * 1024.0)
                fileSizeStr = String(format: "%.1f MB", mb)
            } else {
                let subs = r["subscriptions"] as? Int ?? (r["subscriptions"] as? String).flatMap(Int.init) ?? 0
                fileSizeStr = subs > 1000 ? String(format: "%.1fk subs", Double(subs) / 1000.0) : "\(subs) subs"
            }

            // 3. Category Detection from Steam tags
            var category = query.isEmpty ? "Steam Workshop" : "Steam (\(query.capitalized))"
            for t in tagsList {
                let tl = t.lowercased()
                if tl.contains("anime") || tl.contains("manga") {
                    category = "Anime & Manga"; break
                } else if tl.contains("game") || tl.contains("gaming") {
                    category = "Gaming"; break
                } else if tl.contains("cyberpunk") || tl.contains("sci-fi") || tl.contains("future") {
                    category = "Sci-Fi & Cyberpunk"; break
                } else if tl.contains("nature") || tl.contains("space") || tl.contains("landscape") {
                    category = "Nature & Space"; break
                } else if tl.contains("lofi") || tl.contains("relax") || tl.contains("aesthetic") || tl.contains("cozy") {
                    category = "Lofi & Aesthetic"; break
                } else if tl.contains("car") || tl.contains("vehicle") {
                    category = "Cars & Vehicles"; break
                } else if tl.contains("fantasy") || tl.contains("abstract") {
                    category = "Fantasy & Abstract"; break
                }
            }
            if category.hasPrefix("Steam") {
                if let inferred = CatalogService.inferCategory(for: title) {
                    category = inferred
                }
            }

            // 4. Cross-match with curated high-bitrate video stream if available
            var videoDownloadURL = previewURL
            var videoPreviewURL = previewURL
            let cleanTitle = title.lowercased().trimmingCharacters(in: .whitespaces)

            if let curated = CatalogService.shared.steamWallpaperEngineItems.first(where: {
                let cTitle = $0.title.lowercased().trimmingCharacters(in: .whitespaces)
                return cTitle == cleanTitle || cleanTitle.contains(cTitle) || cTitle.contains(cleanTitle)
            }) {
                videoDownloadURL = curated.downloadURL
                videoPreviewURL = curated.previewURL ?? curated.downloadURL
                resolution = curated.resolution
            }

            items.append(
                CatalogItem(
                    id: "steam-\(id)",
                    title: title,
                    category: category,
                    thumbnailURL: previewURL,
                    previewURL: videoPreviewURL,
                    downloadURL: videoDownloadURL,
                    resolution: resolution,
                    fileSizeString: fileSizeStr,
                    sourceDescription: "Steam Workshop",
                    isLocalCopy: false
                )
            )
        }
        return items
    }
}
