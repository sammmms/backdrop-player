import SwiftUI
import AppKit

public struct GalleryView: View {
    @ObservedObject private var downloader = WallpaperDownloader.shared
    @State private var items: [CatalogItem] = []

    // Multi-select checklists
    @State private var selectedMarketplaces: Set<String> = Set(CatalogService.availableMarketplaces.filter { $0 != "🔗 Custom Video URL" })
    @State private var selectedCategories: Set<String> = Set(CatalogService.availableCategories)

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

    // Sheet for per-wallpaper config
    @State private var configuringItem: CatalogItem?
    @State private var showCustomURLView: Bool = false

    // Live desktop playback rate for sidebar control
    @State private var activeDesktopRate: Double = 1.0

    private let marketplaces = CatalogService.availableMarketplaces.filter { $0 != "🔗 Custom Video URL" }
    private let categories = CatalogService.availableCategories
    private let ratePresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Persistent Sidebar
            sidebarView
                .frame(width: 270)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.85))

            Divider()

            // MARK: - Right Main Content Area
            VStack(spacing: 0) {
                mainTopBar
                Divider()

                if showCustomURLView {
                    directURLView
                } else {
                    galleryGrid
                }

                if let toast = toastMessage {
                    toastBanner(toast)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 1040, minHeight: 700)
        .sheet(item: $configuringItem) { item in
            WallpaperConfigSheet(item: item) {
                configuringItem = nil
                refreshTrigger = UUID()
            }
        }
        .onAppear {
            activeDesktopRate = WallpaperEngine.shared.currentPlaybackRate
            performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WallpaperEngineStateChanged"))) { _ in
            refreshTrigger = UUID()
            activeDesktopRate = WallpaperEngine.shared.currentPlaybackRate
        }
    }

    // MARK: - Left Sidebar

    private var sidebarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Sidebar Header
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.accentColor)
                    Text("Backdrop Hub")
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.top, 14)

                Divider()

                // 2. Active Screen Mini Previews
                VStack(alignment: .leading, spacing: 10) {
                    Text("ACTIVE DISPLAYS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    // Desktop Mini Preview
                    miniDesktopPreviewCard

                    // Lock Screen Mini Preview
                    miniLockScreenPreviewCard
                }

                Divider()

                // 3. Marketplace Checklist
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Marketplaces", systemImage: "globe.americas.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("All") {
                            selectedMarketplaces = Set(marketplaces)
                            performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .font(.system(size: 10))

                        Text("|").font(.system(size: 10)).foregroundColor(.secondary)

                        Button("Clear") {
                            selectedMarketplaces.removeAll()
                            performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .font(.system(size: 10))
                    }

                    ForEach(marketplaces, id: \.self) { m in
                        HStack(spacing: 6) {
                            Button(action: {
                                toggleMarketplace(m)
                            }) {
                                Image(systemName: selectedMarketplaces.contains(m) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedMarketplaces.contains(m) ? .accentColor : .secondary)
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Text(m)
                                .font(.system(size: 11, weight: selectedMarketplaces.contains(m) ? .semibold : .regular))
                                .foregroundColor(selectedMarketplaces.contains(m) ? .primary : .secondary)
                                .lineLimit(1)
                                .onTapGesture {
                                    toggleMarketplace(m)
                                }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                // 4. Category Checklist
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Categories", systemImage: "tag.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("All") {
                            selectedCategories = Set(categories)
                            performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .font(.system(size: 10))

                        Text("|").font(.system(size: 10)).foregroundColor(.secondary)

                        Button("Clear") {
                            selectedCategories.removeAll()
                            performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .font(.system(size: 10))
                    }

                    ForEach(categories, id: \.self) { c in
                        HStack(spacing: 6) {
                            Button(action: {
                                toggleCategory(c)
                            }) {
                                Image(systemName: selectedCategories.contains(c) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedCategories.contains(c) ? .purple : .secondary)
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Text(categoryEmoji(for: c) + " " + c)
                                .font(.system(size: 11, weight: selectedCategories.contains(c) ? .semibold : .regular))
                                .foregroundColor(selectedCategories.contains(c) ? .primary : .secondary)
                                .lineLimit(1)
                                .onTapGesture {
                                    toggleCategory(c)
                                }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                // 5. Actions / Custom URL
                VStack(spacing: 8) {
                    Button(action: {
                        showCustomURLView.toggle()
                    }) {
                        HStack {
                            Image(systemName: "link.badge.plus")
                            Text(showCustomURLView ? "Back to Catalog Grid" : "Custom Video URL...")
                            Spacer()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(showCustomURLView ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.15))
                        .foregroundColor(showCustomURLView ? .white : .primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        selectedMarketplaces = Set(marketplaces)
                        selectedCategories = Set(categories)
                        searchText = ""
                        showCustomURLView = false
                        performLiveMultiSearch(query: "", marketplaces: selectedMarketplaces, categories: selectedCategories)
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Filters")
                            Spacer()
                        }
                        .font(.system(size: 11, weight: .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 14)
        }
    }

    // MARK: - Mini Rendered Previews

    private var desktopItem: WallpaperItem? {
        _ = refreshTrigger
        return WallpaperEngine.shared.currentDesktopWallpaper
    }

    private var lockScreenItem: WallpaperItem? {
        _ = refreshTrigger
        return WallpaperEngine.shared.currentLockScreenWallpaper
    }

    private var currentDesktopTitle: String {
        desktopItem?.title ??
            UserDefaults.standard.string(forKey: "WallpaperEngine.desktopWallpaperTitle") ??
            "Kirby Floating on Pond"
    }

    private var currentLockScreenTitle: String {
        lockScreenItem?.title ??
            UserDefaults.standard.string(forKey: "WallpaperEngine.lockScreenWallpaperTitle") ??
            "Abi Toads (Original)"
    }

    private var miniDesktopPreviewCard: some View {
        let stillImg = WallpaperEngine.shared.stillFrameImage(for: desktopItem)
        let isPlaying = WallpaperEngine.shared.isPlaying

        return VStack(spacing: 6) {
            // Rendered Screen Box
            ZStack(alignment: .topLeading) {
                if let img = stillImg {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 242, height: 110)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 242, height: 110)
                }

                // Top Badges & Controls
                HStack {
                    HStack(spacing: 3) {
                        Image(systemName: "display")
                        Text("Desktop")
                    }
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(4)

                    Spacer()

                    // Play/Pause button
                    Button(action: {
                        WallpaperEngine.shared.togglePlayPause()
                        refreshTrigger = UUID()
                    }) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(isPlaying ? "Pause wallpaper" : "Resume wallpaper")
                }
                .padding(6)

                // Bottom title overlay
                VStack {
                    Spacer()
                    HStack {
                        Text(currentDesktopTitle)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2)
                        Spacer()
                        Text(String(format: "%.2fx", activeDesktopRate))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(3)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .frame(width: 242, height: 110)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.4), lineWidth: 1)
            )

            // Dynamic Playback Speed / Time Scale Slider & Presets for Desktop
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "speedometer")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                    Text("Time Scale: \(String(format: "%.2fx", activeDesktopRate))")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                }

                Slider(value: $activeDesktopRate, in: 0.25...2.50, step: 0.05) { editing in
                    if !editing {
                        WallpaperEngine.shared.setPlaybackRate(activeDesktopRate)
                    }
                }
                .onChange(of: activeDesktopRate) { newRate in
                    WallpaperEngine.shared.setPlaybackRate(newRate)
                }

                // Presets
                HStack(spacing: 3) {
                    ForEach(ratePresets, id: \.self) { p in
                        Button(action: {
                            activeDesktopRate = p
                            WallpaperEngine.shared.setPlaybackRate(p)
                        }) {
                            Text(String(format: "%.1fx", p))
                                .font(.system(size: 9, weight: abs(activeDesktopRate - p) < 0.05 ? .bold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                                .background(abs(activeDesktopRate - p) < 0.05 ? Color.blue : Color(NSColor.separatorColor).opacity(0.2))
                                .foregroundColor(abs(activeDesktopRate - p) < 0.05 ? .white : .primary)
                                .cornerRadius(3)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
    }

    private var miniLockScreenPreviewCard: some View {
        let stillImg = WallpaperEngine.shared.stillFrameImage(for: lockScreenItem)

        return ZStack(alignment: .topLeading) {
            if let img = stillImg {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 242, height: 80)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 242, height: 80)
            }

            // Top Badges
            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill")
                    Text("Lock Screen")
                }
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(4)

                Spacer()
            }
            .padding(6)

            // Bottom title overlay
            VStack {
                Spacer()
                HStack {
                    Text(currentLockScreenTitle)
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(width: 242, height: 80)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.purple.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Right Main Top Bar

    private var mainTopBar: some View {
        HStack(spacing: 12) {
            // Live Search Field
            HStack(spacing: 8) {
                if isSearchingBackend {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                }

                TextField("Search live wallpapers across selected marketplaces...", text: $searchText, onCommit: {
                    performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
                })
                .textFieldStyle(PlainTextFieldStyle())
                .onChange(of: searchText) { newValue in
                    performLiveMultiSearch(query: newValue, marketplaces: selectedMarketplaces, categories: selectedCategories)
                }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        performLiveMultiSearch(query: "", marketplaces: selectedMarketplaces, categories: selectedCategories)
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

            Spacer()

            // Status Pill
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

            // Refresh Button
            Button(action: {
                performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
                showToast("Refreshed live catalog feeds.")
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Refresh Live Marketplaces")
        }
        .padding(14)
    }

    // MARK: - Gallery Grid

    private var galleryGrid: some View {
        ScrollView {
            if isSearchingBackend && items.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 80)
                    ProgressView("Connecting to live marketplaces...")
                    Text("Fetching feeds from selected sources...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 10) {
                    Spacer().frame(height: 80)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No wallpapers found")
                        .font(.headline)
                    Text("Try adjusting your keyword, checking more marketplaces, or categories in the sidebar.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 340), spacing: 16)], spacing: 16) {
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

                // Infinite Scroll Bottom Trigger
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
        let savedSpeed = WallpaperEngine.shared.getPlaybackRate(for: item.id)

        return VStack(alignment: .leading, spacing: 10) {
            // Preview Thumbnail
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

                // Resolution & Badges
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

                    if abs(savedSpeed - 1.0) > 0.05 {
                        Text(String(format: "%.2fx", savedSpeed))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.85))
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

                    // Button 3: Configuration (Time Scale / Speed / Audio)
                    Button(action: {
                        configuringItem = item
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Configure Playback Speed (Time Scale), Audio, and Scaling")

                    // Button 4: More actions menu
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

                        Button(action: {
                            configuringItem = item
                        }) {
                            Label("Configure Wallpaper Settings...", systemImage: "gearshape")
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

    private func categoryEmoji(for category: String) -> String {
        switch category {
        case "Anime & Manga": return "🌸"
        case "Gaming": return "🎮"
        case "Sci-Fi & Cyberpunk": return "🤖"
        case "Nature & Space": return "🌲"
        case "Lofi & Aesthetic": return "☕"
        case "Cars & Vehicles": return "🏎️"
        case "Fantasy & Abstract": return "🎨"
        default: return "🏷️"
        }
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
                showCustomURLView = false
            }
        }
    }

    // MARK: - Filter Toggles & Multi Search

    private func toggleMarketplace(_ m: String) {
        if selectedMarketplaces.contains(m) {
            selectedMarketplaces.remove(m)
        } else {
            selectedMarketplaces.insert(m)
        }
        performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
    }

    private func toggleCategory(_ c: String) {
        if selectedCategories.contains(c) {
            selectedCategories.remove(c)
        } else {
            selectedCategories.insert(c)
        }
        performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
    }

    private func performLiveMultiSearch(query: String, marketplaces: Set<String>, categories: Set<String>) {
        searchTask?.cancel()
        isSearchingBackend = true
        currentPage = 1
        canLoadMore = true

        searchTask = Task {
            if !query.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            guard !Task.isCancelled else { return }

            let results = await CatalogService.shared.searchLiveMulti(
                query: query,
                marketplaces: marketplaces,
                categories: categories,
                page: 1
            )
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
            let newItems = await CatalogService.shared.searchLiveMulti(
                query: searchText,
                marketplaces: selectedMarketplaces,
                categories: selectedCategories,
                page: nextPage
            )

            await MainActor.run {
                if newItems.isEmpty {
                    self.canLoadMore = false
                } else {
                    var existingTitles = Set(self.items.map { $0.title.lowercased() })
                    var toAppend: [CatalogItem] = []
                    for item in newItems {
                        let key = item.title.lowercased()
                        if !existingTitles.contains(key) {
                            existingTitles.insert(key)
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
