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

            let subs = r["subscriptions"] as? Int ?? (r["subscriptions"] as? String).flatMap(Int.init) ?? 0
            let subsFormatted = subs > 1000 ? String(format: "%.1fk subs", Double(subs) / 1000.0) : "\(subs) subs"
            let category = query.isEmpty ? "Steam Workshop" : "Steam (\(query.capitalized))"

            items.append(
                CatalogItem(
                    id: "steam-\(id)",
                    title: title,
                    category: category,
                    thumbnailURL: previewURL,
                    previewURL: previewURL,
                    downloadURL: previewURL,
                    resolution: "HD Loop",
                    fileSizeString: subsFormatted,
                    sourceDescription: "Steam Workshop",
                    isLocalCopy: false
                )
            )
        }
        return items
    }
}
