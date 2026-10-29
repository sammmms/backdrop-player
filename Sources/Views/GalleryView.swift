import SwiftUI
import AppKit

public struct GalleryView: View {
    @ObservedObject private var downloader = WallpaperDownloader.shared
    @State private var items: [CatalogItem] = []
    @State private var selectedCategory: String = "All"
    @State private var searchText: String = ""
    @State private var customURLText: String = ""
    @State private var customTitleText: String = ""
    @State private var toastMessage: String?

    private let categories = [
        "All",
        "Backdrop Cache (Instant)",
        "4K Nature",
        "4K Space & Earth",
        "4K Cities",
        "Lofi & Aesthetic",
        "Direct URL"
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            categoryBar
            Divider()

            if selectedCategory == "Direct URL" {
                directURLView
            } else {
                galleryGrid
            }

            if let toast = toastMessage {
                toastBanner(toast)
            }
        }
        .frame(minWidth: 840, minHeight: 580)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadItems()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wallpaper Gallery & Hub")
                    .font(.headline)
                    .fontWeight(.bold)
                Text("Browse, download, and apply live 4K wallpapers directly to your Mac desktop.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search wallpapers...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .frame(width: 220)
        }
        .padding(16)
    }

    // MARK: - Category Bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    Button(action: {
                        selectedCategory = cat
                    }) {
                        Text(cat)
                            .font(.system(size: 12, weight: selectedCategory == cat ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedCategory == cat
                                    ? Color.accentColor
                                    : Color(NSColor.controlBackgroundColor)
                            )
                            .foregroundColor(
                                selectedCategory == cat
                                    ? .white
                                    : .primary
                            )
                            .cornerRadius(14)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Grid View

    private var filteredItems: [CatalogItem] {
        items.filter { item in
            let matchesCategory = (selectedCategory == "All") ||
                (selectedCategory == "Backdrop Cache (Instant)" && item.isLocalCopy) ||
                (item.category.contains(selectedCategory))

            let matchesSearch = searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.category.localizedCaseInsensitiveContains(searchText)

            return matchesCategory && matchesSearch
        }
    }

    private var galleryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 300), spacing: 16)], spacing: 16) {
                ForEach(filteredItems) { item in
                    wallpaperCard(for: item)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Wallpaper Card

    private func wallpaperCard(for item: CatalogItem) -> some View {
        let isDownloaded = downloader.isDownloaded(item: item)
        let isCurrent = WallpaperEngine.shared.currentWallpaper?.title == item.title
        let progress = downloader.downloadProgress[item.id]
        let status = downloader.downloadStatus[item.id]

        return VStack(alignment: .leading, spacing: 10) {
            // Thumbnail / Icon banner
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    gradient: Gradient(colors: gradientColors(for: item)),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 120)
                .cornerRadius(8)
                .overlay(
                    Image(systemName: iconForCategory(item.category))
                        .font(.system(size: 38))
                        .foregroundColor(.white.opacity(0.85))
                )

                // Badges
                HStack(spacing: 4) {
                    Text(item.resolution)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)

                    Text(item.fileSizeString)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                Text("\(item.category) • \(item.sourceDescription)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Action Button
            if let p = progress {
                VStack(spacing: 4) {
                    ProgressView(value: p)
                        .progressViewStyle(LinearProgressViewStyle())
                    if let st = status {
                        Text(st)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            } else if isCurrent {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Active Wallpaper")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12))
                .cornerRadius(6)
            } else if isDownloaded {
                Button(action: {
                    downloader.downloadAndApply(item: item) { success in
                        if success { showToast("Applied \"\(item.title)\"!") }
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Apply to Desktop")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Button(action: {
                    downloader.downloadAndApply(item: item) { success in
                        if success { showToast("Downloaded and applied \"\(item.title)\"!") }
                    }
                }) {
                    HStack {
                        Image(systemName: item.isLocalCopy ? "bolt.fill" : "arrow.down.circle.fill")
                        Text(item.isLocalCopy ? "Import & Apply" : "Download & Set")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(item.isLocalCopy ? Color.blue : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Direct URL Downloader

    private var directURLView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Download from Custom Video URL")
                .font(.title3)
                .fontWeight(.bold)

            Text("Paste any direct video link (.mp4, .mov, .m4v, .webm) from Wallpaper Engine, MoeWalls, YouTube rips, or your own server to download and apply directly as your desktop wallpaper.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Wallpaper Title:")
                    .font(.system(size: 12, weight: .semibold))
                TextField("e.g. Neon City Cyberpunk", text: $customTitleText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Video URL:")
                    .font(.system(size: 12, weight: .semibold))
                TextField("https://example.com/video.mp4", text: $customURLText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            Button(action: downloadCustomURL) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Download & Set as Wallpaper")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(customURLText.isEmpty ? Color.gray : Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(customURLText.isEmpty)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 600, alignment: .leading)
    }

    private func downloadCustomURL() {
        guard let url = URL(string: customURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let title = customTitleText.isEmpty ? url.deletingPathExtension().lastPathComponent : customTitleText

        let item = CatalogItem(
            id: UUID().uuidString,
            title: title,
            category: "Custom Web",
            downloadURL: url,
            resolution: "HD",
            fileSizeString: "Online",
            sourceDescription: "Direct Download",
            isLocalCopy: false
        )

        downloader.downloadAndApply(item: item) { success in
            if success {
                showToast("Custom wallpaper \"\(title)\" downloaded and set!")
                customURLText = ""
                customTitleText = ""
            }
        }
    }

    // MARK: - Helpers

    private func loadItems() {
        items = CatalogService.shared.fetchCatalog()
    }

    private func showToast(_ msg: String) {
        withAnimation {
            toastMessage = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                toastMessage = nil
            }
        }
    }

    private func toastBanner(_ msg: String) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(msg)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(radius: 5)
        .padding(.bottom, 12)
    }

    private func iconForCategory(_ category: String) -> String {
        if category.contains("Space") || category.contains("Earth") { return "globe.americas.fill" }
        if category.contains("Nature") { return "leaf.fill" }
        if category.contains("Cities") { return "building.2.fill" }
        if category.contains("Gaming") { return "gamecontroller.fill" }
        if category.contains("Anime") { return "sparkles" }
        return "play.rectangle.fill"
    }

    private func gradientColors(for item: CatalogItem) -> [Color] {
        if item.category.contains("Space") { return [Color.purple.opacity(0.8), Color.blue.opacity(0.8)] }
        if item.category.contains("Nature") { return [Color.green.opacity(0.8), Color.teal.opacity(0.8)] }
        if item.category.contains("Cities") { return [Color.orange.opacity(0.8), Color.red.opacity(0.8)] }
        if item.category.contains("Backdrop") { return [Color.pink.opacity(0.8), Color.purple.opacity(0.8)] }
        return [Color.blue.opacity(0.8), Color.indigo.opacity(0.8)]
    }
}
