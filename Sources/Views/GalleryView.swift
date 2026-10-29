import SwiftUI
import AppKit

public struct GalleryView: View {
    @ObservedObject private var downloader = WallpaperDownloader.shared
    @State private var items: [CatalogItem] = []
    @State private var selectedCategory: String = "🔥 Steam / Wallpaper Engine"
    @State private var searchText: String = ""
    @State private var customURLText: String = ""
    @State private var customTitleText: String = ""
    @State private var toastMessage: String?
    @State private var refreshTrigger: UUID = UUID()

    private let categories = [
        "🔥 Steam / Wallpaper Engine",
        "All",
        "Backdrop Collection",
        "Anime & Gaming",
        "4K Nature & Space",
        "Lofi & Aesthetic",
        "Downloaded / Ready",
        "Custom URL"
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            categoryBar
            Divider()

            if selectedCategory == "Custom URL" {
                directURLView
            } else {
                galleryGrid
            }

            if let toast = toastMessage {
                toastBanner(toast)
            }
        }
        .frame(minWidth: 960, minHeight: 660)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WallpaperEngineStateChanged"))) { _ in
            refreshTrigger = UUID()
        }
    }

    // MARK: - Header

    private var currentDesktopTitle: String {
        WallpaperEngine.shared.currentDesktopWallpaper?.title ??
            UserDefaults.standard.string(forKey: "WallpaperEngine.desktopWallpaperTitle") ??
            "None"
    }

    private var currentLockScreenTitle: String {
        WallpaperEngine.shared.currentLockScreenWallpaper?.title ??
            UserDefaults.standard.string(forKey: "WallpaperEngine.lockScreenWallpaperTitle") ??
            "Abi Toads"
    }

    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text("Wallpaper Gallery & Steam Workshop")
                    .font(.title3)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "display")
                            .foregroundColor(.blue)
                        Text("Desktop: \(currentDesktopTitle)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(4)

                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.purple)
                        Text("Lock Screen: \(currentLockScreenTitle)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(4)
                }
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
            .frame(width: 240)

            Button(action: {
                loadItems()
                showToast("Library refreshed!")
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Refresh Library")
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

    // MARK: - Filtered Items

    private var filteredItems: [CatalogItem] {
        _ = refreshTrigger
        return items.filter { item in
            let matchesCategory: Bool
            switch selectedCategory {
            case "All":
                matchesCategory = true
            case "🔥 Steam / Wallpaper Engine":
                matchesCategory = item.category.contains("Steam") || item.category.contains("Wallpaper Engine")
            case "Backdrop Collection":
                matchesCategory = item.category.contains("Backdrop") || item.sourceDescription.contains("Mac Cache") || item.sourceDescription.contains("Ready on Mac")
            case "Anime & Gaming":
                matchesCategory = item.category.contains("Anime") || item.category.contains("Gaming")
            case "4K Nature & Space":
                matchesCategory = item.category.contains("4K") || item.category.contains("Nature") || item.category.contains("Space")
            case "Lofi & Aesthetic":
                matchesCategory = item.category.contains("Lofi") || item.category.contains("Aesthetic")
            case "Downloaded / Ready":
                matchesCategory = downloader.isDownloaded(item: item) || item.isLocalCopy
            default:
                matchesCategory = item.category.contains(selectedCategory)
            }

            let matchesSearch = searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.category.localizedCaseInsensitiveContains(searchText) ||
                item.sourceDescription.localizedCaseInsensitiveContains(searchText)

            return matchesCategory && matchesSearch
        }
    }

    // MARK: - Grid View

    private var galleryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 330), spacing: 16)], spacing: 16) {
                ForEach(filteredItems) { item in
                    wallpaperCard(for: item)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Wallpaper Card

    private func wallpaperCard(for item: CatalogItem) -> some View {
        let isDownloaded = downloader.isDownloaded(item: item) || item.isLocalCopy
        let isDesktop = currentDesktopTitle.lowercased().contains(item.title.lowercased()) ||
            item.title.lowercased().contains(currentDesktopTitle.lowercased())
        let isLockScreen = currentLockScreenTitle.lowercased().contains(item.title.lowercased()) ||
            item.title.lowercased().contains(currentLockScreenTitle.lowercased())
        let progress = downloader.downloadProgress[item.id]
        let status = downloader.downloadStatus[item.id]

        return VStack(alignment: .leading, spacing: 10) {
            // Real Preview Thumbnail
            ZStack(alignment: .topTrailing) {
                ThumbnailImageView(item: item)
                    .frame(height: 140)
                    .cornerRadius(8)

                // Active badges (Desktop / Lock Screen)
                HStack(spacing: 4) {
                    if isDesktop {
                        HStack(spacing: 2) {
                            Image(systemName: "display")
                            Text("Desktop")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    }

                    if isLockScreen {
                        HStack(spacing: 2) {
                            Image(systemName: "lock.fill")
                            Text("Lock Screen")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .topLeading)

                // Resolution & Size Badges
                HStack(spacing: 4) {
                    if isDownloaded {
                        Text("SAVED")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }

                    Text(item.resolution)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(4)

                    Text(item.fileSizeString)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                .padding(6)
            }

            // Info Section
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                Text("\(item.category) • \(item.sourceDescription)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Download Progress or Action Buttons
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
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 6) {
                    // Button 1: Set Desktop
                    Button(action: {
                        downloader.downloadAndApply(item: item, target: .desktop) { success in
                            if success {
                                showToast("🖥️ Set \"\(item.title)\" as Desktop wallpaper!")
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isDesktop ? "checkmark.circle.fill" : "display")
                            Text(isDesktop ? "Active" : "Set Desktop")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isDesktop ? Color.blue : Color.blue.opacity(0.15))
                        .foregroundColor(isDesktop ? .white : .blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Button 2: Set Lock Screen
                    Button(action: {
                        downloader.downloadAndApply(item: item, target: .lockScreen) { success in
                            if success {
                                showToast("🔒 Set \"\(item.title)\" as Lock Screen!")
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isLockScreen ? "checkmark.shield.fill" : "lock.fill")
                            Text(isLockScreen ? "Lock Active" : "Set Lock")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isLockScreen ? Color.purple : Color.purple.opacity(0.15))
                        .foregroundColor(isLockScreen ? .white : .purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Button 3: Set Both Menu
                    Menu {
                        Button("Set as Desktop & Lock Screen") {
                            downloader.downloadAndApply(item: item, target: .both) { success in
                                if success {
                                    showToast("Applied \"\(item.title)\" to Desktop & Lock Screen!")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .frame(width: 24)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isDesktop ? Color.blue.opacity(0.6) :
                    isLockScreen ? Color.purple.opacity(0.6) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }

    // MARK: - Direct URL Downloader

    private var directURLView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Download from Custom Video URL")
                .font(.title3)
                .fontWeight(.bold)

            Text("Paste any direct video link (.mp4, .mov, .m4v, .webm) from Wallpaper Engine, Steam Workshop mirror, or your own server to download and apply.")
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

            HStack(spacing: 12) {
                Button(action: { downloadCustomURL(target: .desktop) }) {
                    HStack {
                        Image(systemName: "display")
                        Text("Download as Desktop")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(customURLText.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(customURLText.isEmpty)

                Button(action: { downloadCustomURL(target: .lockScreen) }) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Download as Lock Screen")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(customURLText.isEmpty ? Color.gray : Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(customURLText.isEmpty)
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 600, alignment: .leading)
    }

    private func downloadCustomURL(target: WallpaperDownloader.ApplyTarget) {
        guard let url = URL(string: customURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let title = customTitleText.isEmpty ? url.deletingPathExtension().lastPathComponent : customTitleText

        let item = CatalogItem(
            id: UUID().uuidString,
            title: title,
            category: "Custom Web",
            thumbnailURL: nil,
            previewURL: url,
            downloadURL: url,
            resolution: "HD",
            fileSizeString: "Online",
            sourceDescription: "Direct Download",
            isLocalCopy: false
        )

        downloader.downloadAndApply(item: item, target: target) { success in
            if success {
                showToast("Custom wallpaper \"\(title)\" set!")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
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
}
