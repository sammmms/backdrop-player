import Foundation
import SQLite3

public final class BackdropLibraryService {
    public static let shared = BackdropLibraryService()

    public let defaultAssetsDirectory: URL
    public let defaultDatabaseURL: URL

    private var directorySource: DispatchSourceFileSystemObject?
    private var customItemsKey = "BackdropPlayer.CustomWallpapers"

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.defaultAssetsDirectory = home
            .appendingPathComponent("Library/Application Support/Backdrop/Library/Assets")
        self.defaultDatabaseURL = home
            .appendingPathComponent("Library/Application Support/Backdrop/Backdrop.sqlite")
    }

    public func fetchWallpapers() -> [WallpaperItem] {
        var items: [WallpaperItem] = []
        var foundIDs = Set<String>()

        // 1. Fetch from SQLite if available
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

                    // Check if file exists in assets directory
                    if let fileURL = locateAssetFile(id: id) {
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

        // 2. Also check for files directly in Assets folder that may not be in DB
        if FileManager.default.fileExists(atPath: defaultAssetsDirectory.path) {
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: defaultAssetsDirectory,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                )

                for url in fileURLs {
                    let baseName = url.deletingPathExtension().lastPathComponent
                    if !foundIDs.contains(baseName) {
                        let ext = url.pathExtension.lowercased()
                        let isVideo = ["mov", "mp4", "m4v", "webm"].contains(ext)
                        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

                        items.append(
                            WallpaperItem(
                                id: baseName,
                                title: baseName,
                                type: isVideo ? .video : .image,
                                fileURL: url,
                                fileSize: Int64(size),
                                isCustom: false
                            )
                        )
                    }
                }
            } catch {
                print("Error scanning assets directory: \(error)")
            }
        }

        // 3. Include custom user-selected items
        let customItems = loadCustomItems()
        items.append(contentsOf: customItems)

        return items
    }

    private func locateAssetFile(id: String) -> URL? {
        let extensions = ["mov", "mp4", "m4v", "heic", "png", "jpg", "jpeg"]
        for ext in extensions {
            let candidate = defaultAssetsDirectory.appendingPathComponent("\(id).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
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

        guard FileManager.default.fileExists(atPath: defaultAssetsDirectory.path) else { return }

        let descriptor = open(defaultAssetsDirectory.path, O_EVTONLY)
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
