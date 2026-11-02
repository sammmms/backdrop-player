import Foundation

public final class DesktopHutBackendService {
    public static let shared = DesktopHutBackendService()

    private init() {}

    public func search(query: String, category: String = "All Categories", page: Int = 1) async -> [CatalogItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString: String

        if !trimmed.isEmpty {
            let enc = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            urlString = page > 1 ? "https://www.desktophut.com/search/\(enc)?page=\(page)" : "https://www.desktophut.com/search/\(enc)"
        } else {
            let catSlug = categorySlug(for: category)
            urlString = page > 1 ? "https://www.desktophut.com/\(catSlug)?page=\(page)" : "https://www.desktophut.com/\(catSlug)"
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
        case let c where c.contains("anime"): return "category/anime-live-wallpapers"
        case let c where c.contains("game"): return "category/games-live-wallpapers"
        case let c where c.contains("nature") || c.contains("space"): return "category/nature-live-wallpapers"
        case let c where c.contains("lofi") || c.contains("aesthetic"): return "category/Lofi"
        case let c where c.contains("car") || c.contains("vehicle"): return "category/cars-motorcycles-live-wallpapers"
        case let c where c.contains("sci-fi") || c.contains("cyber"): return "category/tech-live-wallpapers"
        default: return "category/Animated-Wallpapers"
        }
    }

    private func parseHTMLCards(html: String, defaultCategory: String) -> [CatalogItem] {
        let pattern = #"<a href="(/[^"]+)" class="wallpaper-card" title="([^"]+)"[\s\S]*?<img src="([^"]+)"[\s\S]*?data-src="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var items: [CatalogItem] = []
        var seen = Set<String>()

        for m in matches {
            guard let hrefRange = Range(m.range(at: 1), in: html),
                  let titleRange = Range(m.range(at: 2), in: html),
                  let imgRange = Range(m.range(at: 3), in: html),
                  let vidRange = Range(m.range(at: 4), in: html) else { continue }

            var title = String(html[titleRange])
            if let dashIdx = title.range(of: " — animated")?.lowerBound {
                title = String(title[..<dashIdx])
            }
            title = title
                .replacingOccurrences(of: "&#8217;", with: "'")
                .replacingOccurrences(of: "&#8216;", with: "'")
                .replacingOccurrences(of: "&#8220;", with: "\"")
                .replacingOccurrences(of: "&#8221;", with: "\"")
                .replacingOccurrences(of: "&#038;", with: "&")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !seen.contains(title.lowercased()) else { continue }
            seen.insert(title.lowercased())

            let href = "https://www.desktophut.com" + String(html[hrefRange])
            let img = String(html[imgRange])
            let vid = String(html[vidRange])

            let slug = String(html[hrefRange]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let thumbURL = URL(string: img)
            let pageURL = URL(string: href) ?? URL(string: "https://www.desktophut.com")!
            let previewVideoURL = URL(string: vid)

            items.append(
                CatalogItem(
                    id: "dh-\(slug)",
                    title: title,
                    category: defaultCategory == "All Categories" ? "Gaming & Tech" : defaultCategory,
                    thumbnailURL: thumbURL,
                    previewURL: previewVideoURL,
                    downloadURL: pageURL,
                    resolution: "4K / 1080p MP4",
                    fileSizeString: "DesktopHut",
                    sourceDescription: "DesktopHut (4K PC)",
                    isLocalCopy: false
                )
            )
        }
        return items
    }

    public func resolveHighResDownloadURL(from pageURLString: String) async -> URL? {
        if pageURLString.contains("/files/") && pageURLString.hasSuffix(".mp4") {
            return URL(string: pageURLString)
        }

        guard let url = URL(string: pageURLString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10.0

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return nil }

        // Strategy 1: primaryDownloadBtn href (href can be before or after id)
        let btnPatterns = [
            #"<a\s+[^>]*href=["']([^"']+\.mp4)["'][^>]*id=["']primaryDownloadBtn["']"#,
            #"<a\s+[^>]*id=["']primaryDownloadBtn["'][^>]*href=["']([^"']+\.mp4)["']"#
        ]
        for pat in btnPatterns {
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let r = Range(match.range(at: 1), in: html) {
                let link = String(html[r])
                if let u = URL(string: link) { return u }
            }
        }

        // Strategy 2: "contentUrl": "https://...desktophut.com/files/...mp4"
        let contentUrlPat = #""contentUrl":\s*"([^"]+\.mp4)""#
        if let regex = try? NSRegularExpression(pattern: contentUrlPat, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let r = Range(match.range(at: 1), in: html) {
            let link = String(html[r]).replacingOccurrences(of: "\\/", with: "/")
            if let u = URL(string: link) { return u }
        }

        // Strategy 3: Any https://(media.|www.)?desktophut.com/files/...mp4 link
        let filesPat = #"https://(?:media\.|www\.)?desktophut\.com/files/[^\s"'<>\\]+\.mp4"#
        if let regex = try? NSRegularExpression(pattern: filesPat, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let r = Range(match.range(at: 0), in: html) {
            let link = String(html[r]).replacingOccurrences(of: "\\/", with: "/")
            if let u = URL(string: link) { return u }
        }

        // Strategy 4: Fallback to player video if present (for scene-based cards)
        let playerPat = #"https://(?:media\.|www\.)?desktophut\.com/previews/[^\s"'<>\\]+-player\.mp4"#
        if let regex = try? NSRegularExpression(pattern: playerPat, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let r = Range(match.range(at: 0), in: html) {
            let link = String(html[r]).replacingOccurrences(of: "\\/", with: "/")
            if let u = URL(string: link) { return u }
        }

        return nil
    }
}
