import Foundation
import Combine
import AppKit

public final class WallpaperDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = WallpaperDownloader()

    public enum ApplyTarget: Sendable {
        case desktop
        case lockScreen
        case both
    }

    @Published public var downloadProgress: [String: Double] = [:]
    @Published public var downloadStatus: [String: String] = [:]

    private var activeTasks: [Int: (item: CatalogItem, target: ApplyTarget, completion: (Bool) -> Void)] = [:]
    private var session: URLSession!

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }

    // MARK: - Magic Bytes File Type Detector

    public static func detectFileType(at url: URL) -> (ext: String, isVideo: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 32) else {
            let ext = url.pathExtension.lowercased()
            let isVid = ["mov", "mp4", "m4v", "webm"].contains(ext)
            return (ext.isEmpty ? "mp4" : ext, isVid)
        }
        try? handle.close()

        // 1. JPEG (FF D8 FF)
        if data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
            return ("jpg", false)
        }
        // 2. PNG (89 50 4E 47)
        if data.count >= 4 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 {
            return ("png", false)
        }
        // 3. GIF (47 49 46 38)
        if data.count >= 4 && data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38 {
            return ("gif", false)
        }
        // 4. MP4 / MOV (ftyp box at offset 4: 66 74 79 70)
        if data.count >= 8 && data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70 {
            return ("mp4", true)
        }
        // 5. WebM / Matroska (1A 45 DF A3)
        if data.count >= 4 && data[0] == 0x1A && data[1] == 0x45 && data[2] == 0xDF && data[3] == 0xA3 {
            return ("webm", true)
        }

        let fallbackExt = url.pathExtension.lowercased()
        let isVid = ["mov", "mp4", "m4v", "webm"].contains(fallbackExt)
        return (fallbackExt.isEmpty ? "mp4" : fallbackExt, isVid)
    }

    public func isDownloaded(item: CatalogItem) -> Bool {
        let destURL = destinationURL(for: item)
        return FileManager.default.fileExists(atPath: destURL.path)
    }

    public func destinationURL(for item: CatalogItem, ext: String? = nil) -> URL {
        let safeTitle = item.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let dir = BackdropLibraryService.shared.localWallpapersDirectory

        if let explicitExt = ext {
            return dir.appendingPathComponent("\(safeTitle).\(explicitExt)")
        }

        // Check if file already exists with any valid extension
        let supportedExtensions = ["mp4", "mov", "gif", "jpg", "jpeg", "png", "heic", "webm"]
        for e in supportedExtensions {
            let candidate = dir.appendingPathComponent("\(safeTitle).\(e)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        var pathExt = item.downloadURL.pathExtension.lowercased()
        if pathExt.isEmpty || pathExt == "php" || pathExt.count > 5 {
            pathExt = "mp4"
        }
        return dir.appendingPathComponent("\(safeTitle).\(pathExt)")
    }

    public func downloadAndApply(
        item: CatalogItem,
        target: ApplyTarget = .desktop,
        completion: @escaping (Bool) -> Void
    ) {
        let dir = BackdropLibraryService.shared.localWallpapersDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dest = destinationURL(for: item)

        // 1. Fast path: Already downloaded and exists on disk
        if FileManager.default.fileExists(atPath: dest.path) {
            applyDownloaded(item: item, fileURL: dest, target: target)
            completion(true)
            return
        }

        // 2. Fast path: Local copy (Pre-installed Backdrop assets or local files)
        if item.isLocalCopy && FileManager.default.fileExists(atPath: item.downloadURL.path) {
            applyDownloaded(item: item, fileURL: item.downloadURL, target: target)
            completion(true)
            return
        }

        // 3. DesktopHut: resolve high-res full video if available
        if item.sourceDescription.contains("DesktopHut") && !item.downloadURL.absoluteString.contains("/files/") {
            downloadStatus[item.id] = "Resolving high-res video..."
            downloadProgress[item.id] = 0.05

            Task {
                if let resolved = await DesktopHutBackendService.shared.resolveHighResDownloadURL(from: item.downloadURL.absoluteString) {
                    let resolvedItem = CatalogItem(
                        id: item.id,
                        title: item.title,
                        category: item.category,
                        thumbnailURL: item.thumbnailURL,
                        previewURL: item.previewURL,
                        downloadURL: resolved,
                        resolution: item.resolution,
                        fileSizeString: item.fileSizeString,
                        sourceDescription: item.sourceDescription,
                        isLocalCopy: item.isLocalCopy
                    )
                    DispatchQueue.main.async {
                        self.startRemoteDownload(item: resolvedItem, target: target, completion: completion)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.startRemoteDownload(item: item, target: target, completion: completion)
                    }
                }
            }
            return
        }

        // 4. MoeWalls: resolve direct video URL
        if item.downloadURL.absoluteString.contains("moewalls.com") && !item.downloadURL.absoluteString.contains("download.php") {
            downloadStatus[item.id] = "Resolving video stream..."
            downloadProgress[item.id] = 0.05

            Task {
                if let resolved = await MoeWallsBackendService.shared.resolveDownloadURL(from: item.downloadURL.absoluteString) {
                    let resolvedItem = CatalogItem(
                        id: item.id,
                        title: item.title,
                        category: item.category,
                        thumbnailURL: item.thumbnailURL,
                        previewURL: item.previewURL,
                        downloadURL: resolved,
                        resolution: item.resolution,
                        fileSizeString: item.fileSizeString,
                        sourceDescription: item.sourceDescription,
                        isLocalCopy: item.isLocalCopy
                    )
                    DispatchQueue.main.async {
                        self.startRemoteDownload(item: resolvedItem, target: target, completion: completion)
                    }
                } else if let preview = item.previewURL {
                    let fallbackItem = CatalogItem(
                        id: item.id,
                        title: item.title,
                        category: item.category,
                        thumbnailURL: item.thumbnailURL,
                        previewURL: preview,
                        downloadURL: preview,
                        resolution: item.resolution,
                        fileSizeString: item.fileSizeString,
                        sourceDescription: item.sourceDescription,
                        isLocalCopy: item.isLocalCopy
                    )
                    DispatchQueue.main.async {
                        self.startRemoteDownload(item: fallbackItem, target: target, completion: completion)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.downloadStatus[item.id] = "Could not resolve stream link."
                        completion(false)
                    }
                }
            }
            return
        }

        startRemoteDownload(item: item, target: target, completion: completion)
    }

    private func startRemoteDownload(
        item: CatalogItem,
        target: ApplyTarget,
        completion: @escaping (Bool) -> Void
    ) {
        downloadStatus[item.id] = "Starting download..."
        downloadProgress[item.id] = 0.01

        var request = URLRequest(url: item.downloadURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        request.setValue("wants_mature_content=1; birthtime=786240001", forHTTPHeaderField: "Cookie")

        let task = session.downloadTask(with: request)
        activeTasks[task.taskIdentifier] = (item, target, completion)
        task.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let taskInfo = activeTasks[downloadTask.taskIdentifier] else { return }
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.5

        DispatchQueue.main.async {
            self.downloadProgress[taskInfo.item.id] = progress
            let mb = Double(totalBytesWritten) / (1024 * 1024)
            let totalMb = Double(totalBytesExpectedToWrite) / (1024 * 1024)
            if totalBytesExpectedToWrite > 0 {
                self.downloadStatus[taskInfo.item.id] = String(format: "%.1f MB / %.1f MB (%.0f%%)", mb, totalMb, progress * 100)
            } else {
                self.downloadStatus[taskInfo.item.id] = String(format: "%.1f MB downloaded", mb)
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let taskInfo = activeTasks[downloadTask.taskIdentifier] else { return }

        // Detect real file type from downloaded payload (magic bytes)
        let (actualExt, isVideo) = Self.detectFileType(at: location)
        let dest = destinationURL(for: taskInfo.item, ext: actualExt)

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)

            DispatchQueue.main.async {
                self.downloadProgress.removeValue(forKey: taskInfo.item.id)
                self.downloadStatus.removeValue(forKey: taskInfo.item.id)
                self.applyDownloaded(item: taskInfo.item, fileURL: dest, isVideo: isVideo, target: taskInfo.target)
                taskInfo.completion(true)
            }
        } catch {
            print("[WallpaperDownloader] Move error: \(error)")
            DispatchQueue.main.async {
                self.downloadStatus[taskInfo.item.id] = "Error: \(error.localizedDescription)"
                taskInfo.completion(false)
            }
        }

        activeTasks.removeValue(forKey: downloadTask.taskIdentifier)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error, let taskInfo = activeTasks[task.taskIdentifier] else { return }
        DispatchQueue.main.async {
            self.downloadProgress.removeValue(forKey: taskInfo.item.id)
            self.downloadStatus[taskInfo.item.id] = "Download failed: \(error.localizedDescription)"
            taskInfo.completion(false)
        }
        activeTasks.removeValue(forKey: task.taskIdentifier)
    }

    private func applyDownloaded(item: CatalogItem, fileURL: URL, isVideo: Bool? = nil, target: ApplyTarget) {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let ext = fileURL.pathExtension.lowercased()
        let isVid = isVideo ?? ["mov", "mp4", "m4v", "webm"].contains(ext)

        let wallpaper = WallpaperItem(
            id: item.id,
            title: item.title,
            type: isVid ? .video : .image,
            fileURL: fileURL,
            fileSize: Int64(size),
            isCustom: false
        )

        let rate = WallpaperEngine.shared.getPlaybackRate(for: item.id)

        switch target {
        case .desktop:
            WallpaperEngine.shared.setPlaybackRate(rate, for: wallpaper.id)
            WallpaperEngine.shared.setDesktopWallpaper(wallpaper)
        case .lockScreen:
            WallpaperEngine.shared.setPlaybackRate(rate, for: wallpaper.id)
            WallpaperEngine.shared.setLockScreenWallpaper(wallpaper)
        case .both:
            WallpaperEngine.shared.setPlaybackRate(rate, for: wallpaper.id)
            WallpaperEngine.shared.setBothWallpapers(wallpaper)
        }
    }
}
