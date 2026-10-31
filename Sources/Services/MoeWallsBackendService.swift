import Foundation

public final class MoeWallsBackendService {
    public static let shared = MoeWallsBackendService()

    private init() {}

    public func search(query: String, category: String = "All Categories", page: Int = 1) async -> [CatalogItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString: String

        if !trimmed.isEmpty {
            let enc = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            urlString = page > 1 ? "https://moewalls.com/page/\(page)/?s=\(enc)" : "https://moewalls.com/?s=\(enc)"
        } else {
            let catSlug = categorySlug(for: category)
            if !catSlug.isEmpty {
                urlString = page > 1 ? "https://moewalls.com/\(catSlug)page/\(page)/" : "https://moewalls.com/\(catSlug)"
            } else {
                urlString = page > 1 ? "https://moewalls.com/page/\(page)/" : "https://moewalls.com/"
            }
        }

        guard let url = URL(string: urlString) else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12.0

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return [] }

        return parseHTMLCards(html: html, defaultCategory: category)
    }

    private func categorySlug(for category: String) -> String {
        switch category.lowercased() {
        case let c where c.contains("anime"): return "category/anime/"
        case let c where c.contains("game"): return "category/games/"
        case let c where c.contains("sci-fi") || c.contains("cyber"): return "category/sci-fi/"
        case let c where c.contains("nature") || c.contains("space"): return "category/landscape/"
        case let c where c.contains("lofi") || c.contains("aesthetic"): return "category/lifestyle/"
        case let c where c.contains("car") || c.contains("vehicle"): return "category/vehicle/"
        case let c where c.contains("fantasy") || c.contains("abstract"): return "category/fantasy/"
        default: return ""
        }
    }

    private func parseHTMLCards(html: String, defaultCategory: String) -> [CatalogItem] {
        let pattern = #"<a title="([^"]+)" class="g1-frame" href="([^"]+)"><div class="g1-frame-inner"><img [^>]*src="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var items: [CatalogItem] = []
        var seen = Set<String>()

        for m in matches {
            guard let titleRange = Range(m.range(at: 1), in: html),
                  let pageRange = Range(m.range(at: 2), in: html),
                  let thumbRange = Range(m.range(at: 3), in: html) else { continue }

            var title = String(html[titleRange])
            if let wallIdx = title.range(of: " Live Wallpaper")?.lowerBound {
                title = String(title[..<wallIdx])
            }
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)

            let page = String(html[pageRange])
            let thumb = String(html[thumbRange])

            guard !seen.contains(title.lowercased()) else { continue }
            seen.insert(title.lowercased())

            let slug = page.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/").last ?? UUID().uuidString
            let thumbURL = URL(string: thumb)
            let pageURL = URL(string: page) ?? URL(string: "https://moewalls.com")!

            items.append(
                CatalogItem(
                    id: "moe-\(slug)",
                    title: title,
                    category: defaultCategory == "All Categories" ? "Anime & Aesthetic" : defaultCategory,
                    thumbnailURL: thumbURL,
                    previewURL: thumbURL,
                    downloadURL: pageURL,
                    resolution: "1080p / 4K 60fps",
                    fileSizeString: "MoeWalls",
                    sourceDescription: "MoeWalls (Anime)",
                    isLocalCopy: false
                )
            )
        }
        return items
    }

    public func resolveDownloadURL(from pageURLString: String) async -> URL? {
        guard let url = URL(string: pageURLString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10.0

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }

        // 1. Direct download button token: id="moe-download" ... data-url="XXXX"
        let moePattern = #"id="moe-download"[^>]*data-url="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: moePattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let r = Range(match.range(at: 1), in: html) {
            let dataUrl = String(html[r])
            return URL(string: "https://go.moewalls.com/download.php?video=\(dataUrl)")
        }

        // 2. Fallback to video player source
        let srcPattern = #"<source src="([^"]+)"#
        if let regex = try? NSRegularExpression(pattern: srcPattern),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let r = Range(match.range(at: 1), in: html) {
            var raw = String(html[r])
            if raw.hasPrefix("/") {
                raw = "https://moewalls.com" + raw
            }
            return URL(string: raw)
        }

        return nil
    }
}
