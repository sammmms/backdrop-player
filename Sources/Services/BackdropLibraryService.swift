import Foundation
import SQLite3

public final class BackdropLibraryService {
    public static let shared = BackdropLibraryService()

    public let defaultAssetsDirectory: URL
    public let defaultCacheDirectory: URL
    public let defaultDatabaseURL: URL
    public let localWallpapersDirectory: URL

    private var directorySource: DispatchSourceFileSystemObject?
    private var customItemsKey = "BackdropPlayer.CustomWallpapers"

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.defaultAssetsDirectory = home
            .appendingPathComponent("Library/Application Support/Backdrop/Library/Assets")
        self.defaultCacheDirectory = home
            .appendingPathComponent("Library/Application Support/BackdropWallpaper/.cache")
        self.defaultDatabaseURL = home
            .appendingPathComponent("Library/Application Support/Backdrop/Backdrop.sqlite")
        self.localWallpapersDirectory = home
            .appendingPathComponent("Documents/GitHub/backdrop-player/wallpapers")
    }

    public func fetchWallpapers() -> [WallpaperItem] {
        var items: [WallpaperItem] = []
        var foundIDs = Set<String>()

        // 1. First, check local clean wallpapers directory in project or bundle resources
        let searchDirs = [
            Bundle.main.resourceURL?.appendingPathComponent("wallpapers"),
            localWallpapersDirectory
        ].compactMap { $0 }

        for dir in searchDirs {
            if FileManager.default.fileExists(atPath: dir.path) {
                if let contents = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for url in contents {
                        let ext = url.pathExtension.lowercased()
                        guard ["mov", "mp4", "m4v", "heic", "png", "jpg", "jpeg"].contains(ext) else { continue }
                        let isVideo = ["mov", "mp4", "m4v", "webm"].contains(ext)
                        let title = url.deletingPathExtension().lastPathComponent
                        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        let id = "local-\(title)"

                        if !foundIDs.contains(id) {
                            foundIDs.insert(id)
                            items.append(
                                WallpaperItem(
                                    id: id,
                                    title: title,
                                    type: isVideo ? .video : .image,
                                    fileURL: url,
                                    fileSize: Int64(size),
                                    isCustom: false
                                )
                            )
                        }
                    }
                }
            }
        }

        // 2. Fetch from SQLite if available and find clean decrypted cache or raw files
        let dbPath = defaultDatabaseURL.path
        var db: OpaquePointer?

        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            let query = "SELECT ZIDENTIFIER, ZTITLE, ZTYPE, ZFILESIZE FROM ZBACKDROP ORDER BY ZTITLE COLLATE NOCASE ASC;"
            var statement: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let cId = sqlite3_column_text(statement, 0),
                          let cTitle = sqlite3_column_text(statement, 1) else {
                        continue
                    }
                    let id = String(cString: cId)
                    let title = String(cString: cTitle)
                    let typeString = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "video"
                    let fileSize = sqlite3_column_int64(statement, 3)
                    let type: WallpaperItem.WallpaperType = (typeString == "video") ? .video : .image

                    // If we already added this by title from local directory, skip
                    if items.contains(where: { $0.title.lowercased() == title.lowercased() }) {
                        continue
                    }

                    if let fileURL = locateAssetFile(id: id, title: title) {
                        foundIDs.insert(id)
                        items.append(
                            WallpaperItem(
                                id: id,
                                title: title,
                                type: type,
                                fileURL: fileURL,
                                fileSize: fileSize,
                                isCustom: false
                            )
                        )
                    }
                }
                sqlite3_finalize(statement)
            }
            sqlite3_close(db)
        }

        // 3. Include custom user-selected items
        let customItems = loadCustomItems()
        items.append(contentsOf: customItems)

        return items
    }

    private func locateAssetFile(id: String, title: String) -> URL? {
        // Priority 1: Check .cache folder (this contains the decrypted, clean MOV without watermarks)
        if FileManager.default.fileExists(atPath: defaultCacheDirectory.path) {
            if let cachedFiles = try? FileManager.default.contentsOfDirectory(atPath: defaultCacheDirectory.path) {
                if let match = cachedFiles.first(where: { $0.hasPrefix(id) && $0.hasSuffix(".mov") }) {
                    let cacheURL = defaultCacheDirectory.appendingPathComponent(match)
                    if isValidMedia(url: cacheURL) {
                        return cacheURL
                    }
                }
            }
        }

        // Priority 2: Check raw Assets folder
        let extensions = ["mov", "mp4", "m4v", "heic", "png", "jpg", "jpeg"]
        for ext in extensions {
            let candidate = defaultAssetsDirectory.appendingPathComponent("\(id).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) && isValidMedia(url: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func isValidMedia(url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let headerData = try? handle.read(upToCount: 32), headerData.count >= 8 else { return false }

        // Check for QuickTime 'ftyp' or 'moov' or standard image signatures
        let headerStr = String(decoding: headerData, as: UTF8.self)
        if headerStr.contains("ftyp") || headerStr.contains("moov") || headerStr.contains("wide") {
            return true
        }

        // JPEG / PNG / HEIC check
        let bytes = [UInt8](headerData)
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true } // JPEG
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true } // PNG

        return false
    }

    // MARK: - Custom Items Management

    public func addCustomWallpaper(url: URL) -> WallpaperItem? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let ext = url.pathExtension.lowercased()
        let isVideo = ["mov", "mp4", "m4v", "webm"].contains(ext)
        let isImage = ["heic", "png", "jpg", "jpeg", "webp"].contains(ext)
        guard isVideo || isImage else { return nil }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let title = url.deletingPathExtension().lastPathComponent
        let id = UUID().uuidString

        let item = WallpaperItem(
            id: id,
            title: title,
            type: isVideo ? .video : .image,
            fileURL: url,
            fileSize: Int64(size),
            isCustom: true
        )

        var existing = loadCustomItems()
        existing.removeAll { $0.fileURL.path == url.path }
        existing.insert(item, at: 0)
        saveCustomItems(existing)

        return item
    }

    public func removeCustomWallpaper(id: String) {
        var existing = loadCustomItems()
        existing.removeAll { $0.id == id }
        saveCustomItems(existing)
    }

    private func loadCustomItems() -> [WallpaperItem] {
        guard let data = UserDefaults.standard.data(forKey: customItemsKey) else { return [] }
        guard let list = try? JSONDecoder().decode([SavedCustomItem].self, from: data) else { return [] }

        return list.compactMap { saved in
            let url = URL(fileURLWithPath: saved.path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return WallpaperItem(
                id: saved.id,
                title: saved.title,
                type: saved.type,
                fileURL: url,
                fileSize: saved.fileSize,
                isCustom: true
            )
        }
    }

    private func saveCustomItems(_ items: [WallpaperItem]) {
        let list = items.map {
            SavedCustomItem(
                id: $0.id,
                title: $0.title,
                type: $0.type,
                path: $0.fileURL.path,
                fileSize: $0.fileSize
            )
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: customItemsKey)
        }
    }

    // MARK: - Directory Watcher

    public func startWatching(onChange: @escaping () -> Void) {
        stopWatching()

        let watchTarget = FileManager.default.fileExists(atPath: defaultCacheDirectory.path)
            ? defaultCacheDirectory
            : defaultAssetsDirectory

        guard FileManager.default.fileExists(atPath: watchTarget.path) else { return }

        let descriptor = open(watchTarget.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .link, .rename],
            queue: .main
        )

        source.setEventHandler {
            onChange()
        }

        source.setCancelHandler {
            close(descriptor)
        }

        source.resume()
        self.directorySource = source
    }

    public func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
    }
}

private struct SavedCustomItem: Codable {
    let id: String
    let title: String
    let type: WallpaperItem.WallpaperType
    let path: String
    let fileSize: Int64
}
