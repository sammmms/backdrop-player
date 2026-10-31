import SwiftUI
import AppKit

public struct GalleryView: View {
    @ObservedObject private var downloader = WallpaperDownloader.shared
    @State private var items: [CatalogItem] = []

    // Multi-select checklists for left sidebar
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

    // Applying state per wallpaper item (e.g. "desktop", "lockScreen", "both")
    @State private var applyingItemIds: [String: String] = [:]

    // Right Inspector Sidebar state
    @State private var isInspectorVisible: Bool = true
    // 0 = Desktop, 1 = Lock Screen, 2 = Selected Wallpaper
    @State private var selectedTargetMode: Int = 0
    @State private var selectedItem: CatalogItem?

    // Detached Time Scale & Volume controls
    @State private var desktopRate: Double = 1.0
    @State private var lockScreenRate: Double = 1.0
    @State private var itemRate: Double = 1.0
    @State private var itemVolume: Float = 1.0
    @State private var desktopVolume: Float = 1.0
    @State private var scalingMode: WallpaperScalingMode = .aspectFill

    @State private var showCustomURLView: Bool = false

    private let marketplaces = CatalogService.availableMarketplaces.filter { $0 != "🔗 Custom Video URL" }
    private let categories = CatalogService.availableCategories
    private let ratePresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - 1. Left Sidebar (Marketplaces & Categories Checklist)
            leftSidebarView
                .frame(width: 230)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.85))

            Divider()

            // MARK: - 2. Center Content Area (Search Bar + Gallery Grid)
            VStack(spacing: 0) {
                centerTopBar
                Divider()

                ZStack(alignment: .bottom) {
                    if showCustomURLView {
                        directURLView
                    } else {
                        galleryGrid
                    }

                    if let toast = toastMessage {
                        toastBanner(toast)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            // MARK: - 3. Right Sidebar (Previews at top + Detached Configuration below)
            if isInspectorVisible {
                Divider()
                rightSidebarView
                    .frame(width: 300)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
            }
        }
        .frame(minWidth: 1080, minHeight: 700)
        .onAppear {
            syncRatesFromEngine()
            performLiveMultiSearch(query: searchText, marketplaces: selectedMarketplaces, categories: selectedCategories)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WallpaperEngineStateChanged"))) { _ in
            refreshTrigger = UUID()
            syncRatesFromEngine()
        }
    }

    private func syncRatesFromEngine() {
        desktopRate = WallpaperEngine.shared.desktopPlaybackRate
        lockScreenRate = WallpaperEngine.shared.lockScreenPlaybackRate
        desktopVolume = WallpaperEngine.shared.getVolume()
        scalingMode = WallpaperEngine.shared.scalingMode
    }

    // MARK: - Left Sidebar (Filters Only)

    private var leftSidebarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Logo & Header
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.accentColor)
                    Text("Backdrop Hub")
                        .font(.headline)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.top, 14)

                Divider()

                // Marketplaces Checklist
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
                            Button(action: { toggleMarketplace(m) }) {
                                Image(systemName: selectedMarketplaces.contains(m) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedMarketplaces.contains(m) ? .accentColor : .secondary)
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Text(m)
                                .font(.system(size: 11, weight: selectedMarketplaces.contains(m) ? .semibold : .regular))
                                .foregroundColor(selectedMarketplaces.contains(m) ? .primary : .secondary)
                                .lineLimit(1)
                                .onTapGesture { toggleMarketplace(m) }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                // Categories Checklist
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
                            Button(action: { toggleCategory(c) }) {
                                Image(systemName: selectedCategories.contains(c) ? "checkmark.square.fill" : "square")
                                    .foregroundColor(selectedCategories.contains(c) ? .purple : .secondary)
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(PlainButtonStyle())

                            Text(categoryEmoji(for: c) + " " + c)
                                .font(.system(size: 11, weight: selectedCategories.contains(c) ? .semibold : .regular))
                                .foregroundColor(selectedCategories.contains(c) ? .primary : .secondary)
                                .lineLimit(1)
                                .onTapGesture { toggleCategory(c) }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                // Bottom actions
                VStack(spacing: 8) {
                    Button(action: { showCustomURLView.toggle() }) {
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
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Center Top Bar

    private var centerTopBar: some View {
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

            // Right Inspector Sidebar Toggle
            Button(action: {
                withAnimation { isInspectorVisible.toggle() }
            }) {
                Image(systemName: isInspectorVisible ? "sidebar.right" : "sidebar.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isInspectorVisible ? .accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle Configuration & Previews Sidebar")
        }
        .padding(14)
    }

    // MARK: - Center Gallery Grid

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
        let isApplying = applyingItemIds[item.id]
        let savedSpeed = WallpaperEngine.shared.getPlaybackRate(for: item.id)

        let isConfiguringThis = (selectedTargetMode == 2 && selectedItem?.id == item.id)

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

            // Download Progress / Applying Spinner / Action Buttons
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
            } else if let applyTarget = isApplying {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Setting \(applyTarget)...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 6) {
                    // Button 1: Set Desktop
                    Button(action: {
                        applyWallpaper(item: item, target: .desktop)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())

                    // Button 2: Set Lock Screen
                    Button(action: {
                        applyWallpaper(item: item, target: .lockScreen)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())

                    // Button 3: Configuration (Opens right sidebar for this item)
                    Button(action: {
                        openConfig(for: item)
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(isConfiguringThis ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                            .foregroundColor(isConfiguringThis ? .white : .primary)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Open configuration in Right Sidebar")

                    // Button 4: More actions menu
                    Menu {
                        Button(action: { applyWallpaper(item: item, target: .both) }) {
                            Label("Set Both Desktop & Lock Screen", systemImage: "sparkles")
                        }

                        Button(action: { openConfig(for: item) }) {
                            Label("Configure in Right Sidebar...", systemImage: "gearshape")
                        }

                        if !item.isLocalCopy {
                            Button(action: { NSWorkspace.shared.open(item.downloadURL) }) {
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
                .stroke(isConfiguringThis ? Color.accentColor : (isDesktop || isLockScreen ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.15)), lineWidth: isConfiguringThis ? 2 : 1)
        )
    }

    private func applyWallpaper(item: CatalogItem, target: WallpaperDownloader.ApplyTarget) {
        let label = (target == .desktop) ? "Desktop" : (target == .lockScreen ? "Lock Screen" : "Both")
        applyingItemIds[item.id] = label

        downloader.downloadAndApply(item: item, target: target) { success in
            applyingItemIds.removeValue(forKey: item.id)
            if success {
                showToast("✨ Set \"\(item.title)\" as \(label)!")
                refreshTrigger = UUID()
            } else {
                showToast("⚠️ Failed to set \(label). Check internet connection.")
            }
        }
    }

    private func openConfig(for item: CatalogItem) {
        selectedItem = item
        selectedTargetMode = 2
        itemRate = WallpaperEngine.shared.getPlaybackRate(for: item.id)
        itemVolume = WallpaperEngine.shared.getVolume(for: item.id)
        withAnimation {
            isInspectorVisible = true
        }
    }

    // MARK: - 3. Right Sidebar (Previews at Top + Detached Configuration Below)

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

    private var rightSidebarView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header of Right Sidebar
                HStack {
                    Label("ACTIVE DISPLAYS", systemImage: "display.2")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { withAnimation { isInspectorVisible = false } }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 14)

                // 1. Desktop Mini Preview (TOP)
                miniDesktopRenderBox

                // 2. Lock Screen Mini Preview (TOP)
                miniLockScreenRenderBox

                Divider()
                    .padding(.vertical, 4)

                // 3. Detached Configuration Controls
                detachedConfigurationPanel
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
    }

    // Rendered Desktop Box (Permanently at top of Right Sidebar)
    private var miniDesktopRenderBox: some View {
        let stillImg = WallpaperEngine.shared.stillFrameImage(for: desktopItem)
        let isPlaying = WallpaperEngine.shared.isPlaying
        let isSelected = (selectedTargetMode == 0)

        return VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                if let img = stillImg {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 272, height: 115)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 272, height: 115)
                }

                // Top Badges
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
                }
                .padding(6)

                // Bottom title and speed badge
                VStack {
                    Spacer()
                    HStack {
                        Text(currentDesktopTitle)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2)
                        Spacer()
                        Text(String(format: "%.2fx", desktopRate))
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
            .frame(width: 272, height: 115)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.blue.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedTargetMode = 0
            }

            // Quick Select / Configure Button
            Button(action: { selectedTargetMode = 0 }) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "slider.horizontal.3")
                    Text(isSelected ? "Configuring Desktop Speed" : "Configure Desktop Speed")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                }
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue.opacity(0.15) : Color(NSColor.separatorColor).opacity(0.1))
                .foregroundColor(isSelected ? .blue : .secondary)
                .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // Rendered Lock Screen Box (Permanently at top of Right Sidebar)
    private var miniLockScreenRenderBox: some View {
        let stillImg = WallpaperEngine.shared.stillFrameImage(for: lockScreenItem)
        let isSelected = (selectedTargetMode == 1)

        return VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                if let img = stillImg {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 272, height: 95)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [Color.purple.opacity(0.8), Color.indigo.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 272, height: 95)
                }

                // Top Badge
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

                // Bottom title and rate badge
                VStack {
                    Spacer()
                    HStack {
                        Text(currentLockScreenTitle)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2)
                        Spacer()
                        Text(String(format: "%.2fx", lockScreenRate))
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
            .frame(width: 272, height: 95)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.purple : Color.purple.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedTargetMode = 1
            }

            // Quick Select / Configure Button
            Button(action: { selectedTargetMode = 1 }) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "slider.horizontal.3")
                    Text(isSelected ? "Configuring Lock Screen Speed" : "Configure Lock Screen Speed")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                }
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.purple.opacity(0.15) : Color(NSColor.separatorColor).opacity(0.1))
                .foregroundColor(isSelected ? .purple : .secondary)
                .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // Detached Configuration Panel
    private var detachedConfigurationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Target Selector (Desktop / Lock Screen / Selected Wallpaper)
            VStack(alignment: .leading, spacing: 6) {
                Text("CONFIGURATION TARGET")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                Picker("", selection: $selectedTargetMode) {
                    Text("Desktop").tag(0)
                    Text("Lock Screen").tag(1)
                    if let s = selectedItem {
                        Text(s.title.prefix(8) + "...").tag(2)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Controls based on selectedTargetMode
            if selectedTargetMode == 0 {
                desktopConfigControls
            } else if selectedTargetMode == 1 {
                lockScreenConfigControls
            } else if selectedTargetMode == 2, let item = selectedItem {
                itemConfigControls(item: item)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
    }

    // 1. Desktop Controls (Detached)
    private var desktopConfigControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🖥️ Desktop Time Scale")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text(String(format: "%.2fx", desktopRate))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }

            Text("Adjust live animation speed independently for Desktop (detached from Lock Screen).")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Slider(value: $desktopRate, in: 0.25...2.50, step: 0.05) { editing in
                if !editing {
                    WallpaperEngine.shared.desktopPlaybackRate = desktopRate
                }
            }
            .onChange(of: desktopRate) { newRate in
                WallpaperEngine.shared.desktopPlaybackRate = newRate
            }

            // Presets
            HStack(spacing: 3) {
                ForEach(ratePresets, id: \.self) { p in
                    Button(action: {
                        desktopRate = p
                        WallpaperEngine.shared.desktopPlaybackRate = p
                    }) {
                        Text(String(format: "%.1fx", p))
                            .font(.system(size: 9, weight: abs(desktopRate - p) < 0.05 ? .bold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(abs(desktopRate - p) < 0.05 ? Color.blue : Color(NSColor.separatorColor).opacity(0.2))
                            .foregroundColor(abs(desktopRate - p) < 0.05 ? .white : .primary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Divider()

            // Desktop Audio Volume
            HStack {
                Label("Audio Volume", systemImage: desktopVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(desktopVolume == 0 ? "Muted" : "\(Int(desktopVolume * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }

            HStack(spacing: 8) {
                Button(action: {
                    desktopVolume = (desktopVolume > 0) ? 0.0 : 1.0
                    WallpaperEngine.shared.setVolume(desktopVolume)
                }) {
                    Image(systemName: desktopVolume == 0 ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 11))
                }
                .buttonStyle(PlainButtonStyle())

                Slider(value: $desktopVolume, in: 0.0...1.0, step: 0.05) { editing in
                    if !editing {
                        WallpaperEngine.shared.setVolume(desktopVolume)
                    }
                }
                .onChange(of: desktopVolume) { newVol in
                    WallpaperEngine.shared.setVolume(newVol)
                }
            }

            Divider()

            // Scaling Mode
            Text("Scaling Mode")
                .font(.system(size: 11, weight: .semibold))

            Picker("", selection: $scalingMode) {
                ForEach(WallpaperScalingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: scalingMode) { newMode in
                WallpaperEngine.shared.scalingMode = newMode
            }
        }
    }

    // 2. Lock Screen Controls (Detached)
    private var lockScreenConfigControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🔒 Lock Screen Time Scale")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text(String(format: "%.2fx", lockScreenRate))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
            }

            Text("Adjust speed independently for Lock Screen (detached from Desktop).")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Slider(value: $lockScreenRate, in: 0.25...2.50, step: 0.05) { editing in
                if !editing {
                    WallpaperEngine.shared.lockScreenPlaybackRate = lockScreenRate
                }
            }
            .onChange(of: lockScreenRate) { newRate in
                WallpaperEngine.shared.lockScreenPlaybackRate = newRate
            }

            // Presets
            HStack(spacing: 3) {
                ForEach(ratePresets, id: \.self) { p in
                    Button(action: {
                        lockScreenRate = p
                        WallpaperEngine.shared.lockScreenPlaybackRate = p
                    }) {
                        Text(String(format: "%.1fx", p))
                            .font(.system(size: 9, weight: abs(lockScreenRate - p) < 0.05 ? .bold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(abs(lockScreenRate - p) < 0.05 ? Color.purple : Color(NSColor.separatorColor).opacity(0.2))
                            .foregroundColor(abs(lockScreenRate - p) < 0.05 ? .white : .primary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // 3. Selected Wallpaper Item Controls
    private func itemConfigControls(item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ThumbnailImageView(item: item)
                    .frame(width: 50, height: 35)
                    .cornerRadius(4)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                    Text(item.category)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack {
                Text("Custom Time Scale")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text(String(format: "%.2fx", itemRate))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
            }

            Slider(value: $itemRate, in: 0.25...2.50, step: 0.05) { editing in
                if !editing {
                    WallpaperEngine.shared.setPlaybackRate(itemRate, for: item.id)
                }
            }
            .onChange(of: itemRate) { newRate in
                WallpaperEngine.shared.setPlaybackRate(newRate, for: item.id)
            }

            // Presets
            HStack(spacing: 3) {
                ForEach(ratePresets, id: \.self) { p in
                    Button(action: {
                        itemRate = p
                        WallpaperEngine.shared.setPlaybackRate(p, for: item.id)
                    }) {
                        Text(String(format: "%.1fx", p))
                            .font(.system(size: 9, weight: abs(itemRate - p) < 0.05 ? .bold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                            .background(abs(itemRate - p) < 0.05 ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.2))
                            .foregroundColor(abs(itemRate - p) < 0.05 ? .white : .primary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Divider()

            // Apply buttons
            VStack(spacing: 6) {
                Button(action: {
                    WallpaperEngine.shared.setPlaybackRate(itemRate, for: item.id)
                    applyWallpaper(item: item, target: .desktop)
                }) {
                    HStack {
                        Image(systemName: "display")
                        Text("Apply to Desktop at \(String(format: "%.2fx", itemRate))")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    WallpaperEngine.shared.setPlaybackRate(itemRate, for: item.id)
                    applyWallpaper(item: item, target: .lockScreen)
                }) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Apply to Lock Screen at \(String(format: "%.2fx", itemRate))")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    WallpaperEngine.shared.setPlaybackRate(itemRate, for: item.id)
                    applyWallpaper(item: item, target: .both)
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Apply to Both at \(String(format: "%.2fx", itemRate))")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.indigo)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
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
        .padding(.bottom, 16)
    }
}
