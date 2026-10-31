import SwiftUI
import AppKit

public struct GalleryView: View {
    @ObservedObject private var downloader = WallpaperDownloader.shared
    @State private var items: [CatalogItem] = []
    @State private var selectedMarketplace: String = "🌐 All Marketplaces"
    @State private var selectedCategory: String = "All Categories"
    @State private var searchText: String = ""
    @State private var customURLText: String = ""
    @State private var customTitleText: String = ""
    @State private var toastMessage: String?
    @State private var refreshTrigger: UUID = UUID()
    @State private var isSearchingBackend: Bool = false
    @State private var searchTask: Task<Void, Never>?
    @State private var currentPage: Int = 1
    @State private var isLoadingMore: Bool = false
    @State private var canLoadMore: Bool = true

    private let marketplaces = CatalogService.availableMarketplaces
    private let categories = CatalogService.availableCategories

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            filterBar
            Divider()

            if selectedMarketplace == "🔗 Custom Video URL" {
                directURLView
            } else {
                galleryGrid
            }

            if let toast = toastMessage {
                toastBanner(toast)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            performLiveSearch(query: searchText, marketplace: selectedMarketplace, category: selectedCategory)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WallpaperEngineStateChanged"))) { _ in
            refreshTrigger = UUID()
        }
    }

    // MARK: - Header

    private var currentDesktopTitle: String {
        _ = refreshTrigger
        return WallpaperEngine.shared.currentDesktopWallpaper?.title ??
            UserDefaults.standard.string(forKey: "WallpaperEngine.desktopWallpaperTitle") ??
            "None"
    }

    private var currentLockScreenTitle: String {
        _ = refreshTrigger
        return WallpaperEngine.shared.currentLockScreenWallpaper?.title ??
            UserDefaults.standard.string(forKey: "WallpaperEngine.lockScreenWallpaperTitle") ??
            "Abi Toads"
    }

    private var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text("Live Wallpaper Hub & Marketplaces")
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

            // Live Search Field
            HStack(spacing: 6) {
                if isSearchingBackend {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                }

                TextField("Search live (e.g. toad, cyberpunk, anime)...", text: $searchText, onCommit: {
                    performLiveSearch(query: searchText, marketplace: selectedMarketplace, category: selectedCategory)
                })
                .textFieldStyle(PlainTextFieldStyle())
                .onChange(of: searchText) { newValue in
                    performLiveSearch(query: newValue, marketplace: selectedMarketplace, category: selectedCategory)
                }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        performLiveSearch(query: "", marketplace: selectedMarketplace, category: selectedCategory)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .frame(width: 290)

            Button(action: {
                performLiveSearch(query: searchText, marketplace: selectedMarketplace, category: selectedCategory)
                showToast("Refreshing live connectors...")
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Refresh Live Marketplaces")
        }
        .padding(16)
    }

    // MARK: - Filter Bar (Dropdowns instead of horizontal category tabs)

    private var filterBar: some View {
        HStack(spacing: 12) {
            // 1. Marketplace Filter Dropdown
            Menu {
                ForEach(marketplaces, id: \.self) { m in
                    Button(action: {
                        selectedMarketplace = m
                        performLiveSearch(query: searchText, marketplace: m, category: selectedCategory)
                    }) {
                        HStack {
                            Text(m)
                            if selectedMarketplace == m {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe.americas.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Marketplace")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(selectedMarketplace)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(7)
            }
            .menuStyle(BorderlessButtonMenuStyle())

            // 2. Category Filter Dropdown
            Menu {
                ForEach(categories, id: \.self) { c in
                    Button(action: {
                        selectedCategory = c
                        performLiveSearch(query: searchText, marketplace: selectedMarketplace, category: c)
                    }) {
                        HStack {
                            Text(c)
                            if selectedCategory == c {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Category")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(selectedCategory)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(7)
            }
            .menuStyle(BorderlessButtonMenuStyle())

            // Reset filters button if customized
            if selectedMarketplace != "🌐 All Marketplaces" || selectedCategory != "All Categories" || !searchText.isEmpty {
                Button(action: {
                    selectedMarketplace = "🌐 All Marketplaces"
                    selectedCategory = "All Categories"
                    searchText = ""
                    performLiveSearch(query: "", marketplace: "🌐 All Marketplaces", category: "All Categories")
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset Filters")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer()

            // Result count indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(isSearchingBackend ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)

                if isSearchingBackend {
                    Text("Connecting live...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.18))
                            .foregroundColor(.green)
                            .cornerRadius(3)
                        Text("\(items.count) wallpapers online")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Grid View

    private var galleryGrid: some View {
        ScrollView {
            if isSearchingBackend && items.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 70)
                    ProgressView("Connecting to live marketplace...")
                    Text("Fetching feeds from \(selectedMarketplace)...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 10) {
                    Spacer().frame(height: 70)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No wallpapers found")
                        .font(.headline)
                    Text("Try changing your keyword, marketplace, or category filter.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 330), spacing: 16)], spacing: 16) {
                    ForEach(items) { item in
                        wallpaperCard(for: item)
                            .onAppear {
                                if let idx = items.firstIndex(where: { $0.id == item.id }),
                                   idx >= items.count - 4 {
                                    loadNextPage()
                                }
                            }
                    }
                }
                .padding(16)

                // Infinite Scroll Bottom Indicator & Trigger
                if canLoadMore && !items.isEmpty {
                    VStack(spacing: 8) {
                        if isLoadingMore {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Loading more live wallpapers...")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 16)
                        } else {
                            Button(action: { loadNextPage() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle")
                                    Text("Load More Live Wallpapers (Page \(currentPage + 1))")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.vertical, 16)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Wallpaper Card

    private func wallpaperCard(for item: CatalogItem) -> some View {
        let isDownloaded = downloader.isDownloaded(item: item)
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

                // Resolution & Source Badges
                HStack(spacing: 4) {
                    if isDownloaded {
                        Text("SAVED")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    } else if item.isLocalCopy {
                        Text("LOCAL")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.85))
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

                HStack(spacing: 6) {
                    Button(action: {
                        if !item.isLocalCopy {
                            NSWorkspace.shared.open(item.downloadURL)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text(item.sourceDescription)
                            if !item.isLocalCopy {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8))
                            }
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(sourceBadgeColor(for: item.sourceDescription).opacity(0.15))
                        .foregroundColor(sourceBadgeColor(for: item.sourceDescription))
                        .cornerRadius(3)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Open source on web")

                    Text(item.category)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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
                                showToast("🔒 Set \"\(item.title)\" as Lock Screen wallpaper!")
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isLockScreen ? "checkmark.circle.fill" : "lock.fill")
                            Text(isLockScreen ? "Locked" : "Set Lock")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isLockScreen ? Color.purple : Color.purple.opacity(0.15))
                        .foregroundColor(isLockScreen ? .white : .purple)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Button 3: More actions (Set Both, Open Page)
                    Menu {
                        Button(action: {
                            downloader.downloadAndApply(item: item, target: .both) { success in
                                if success {
                                    showToast("✨ Set \"\(item.title)\" for Both Desktop & Lock Screen!")
                                }
                            }
                        }) {
                            Label("Set Both Desktop & Lock Screen", systemImage: "sparkles")
                        }

                        if !item.isLocalCopy {
                            Button(action: {
                                NSWorkspace.shared.open(item.downloadURL)
                            }) {
                                Label("Open Source Webpage", systemImage: "arrow.up.right.square")
                            }
                        }

                        if isDownloaded {
                            Button(action: {
                                let fileURL = downloader.destinationURL(for: item)
                                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
                            }) {
                                Label("Reveal in Finder", systemImage: "folder")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDesktop || isLockScreen ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private func sourceBadgeColor(for source: String) -> Color {
        if source.contains("Steam") { return .blue }
        if source.contains("MoeWalls") { return .pink }
        if source.contains("DesktopHut") { return .orange }
        if source.contains("Apple") { return .green }
        if source.contains("Wallpaper Engine") { return .indigo }
        return .secondary
    }

    // MARK: - Direct Video URL Downloader

    private var directURLView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Download from Custom Video URL")
                .font(.title3)
                .fontWeight(.bold)

            Text("Paste any direct video link (.mp4, .mov, .m4v, .webm) from any website to download and set as wallpaper.")
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

                Button(action: { downloadCustomURL(target: .both) }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Download for Both")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(customURLText.isEmpty ? Color.gray : Color.indigo)
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

    private func performLiveSearch(query: String, marketplace: String, category: String) {
        searchTask?.cancel()
        isSearchingBackend = true
        currentPage = 1
        canLoadMore = true

        searchTask = Task {
            // Debounce when actively typing text
            if !query.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else { return }

            let results = await CatalogService.shared.searchLive(query: query, marketplace: marketplace, category: category, page: 1)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.items = results
                self.isSearchingBackend = false
                self.canLoadMore = !results.isEmpty
            }
        }
    }

    private func loadNextPage() {
        guard !isLoadingMore && canLoadMore && !isSearchingBackend else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1

        Task {
            let newItems = await CatalogService.shared.searchLive(
                query: searchText,
                marketplace: selectedMarketplace,
                category: selectedCategory,
                page: nextPage
            )

            await MainActor.run {
                if newItems.isEmpty {
                    self.canLoadMore = false
                } else {
                    var existingTitles = Set(self.items.map { $0.title.lowercased() })
                    var toAppend: [CatalogItem] = []
                    for item in newItems {
                        if !existingTitles.contains(item.title.lowercased()) {
                            existingTitles.insert(item.title.lowercased())
                            toAppend.append(item)
                        }
                    }
                    if toAppend.isEmpty {
                        self.canLoadMore = false
                    } else {
                        self.items.append(contentsOf: toAppend)
                        self.currentPage = nextPage
                    }
                }
                self.isLoadingMore = false
            }
        }
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
