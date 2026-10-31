import Foundation
import Combine

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

    public func isDownloaded(item: CatalogItem) -> Bool {
        let destURL = destinationURL(for: item)
        return FileManager.default.fileExists(atPath: destURL.path)
    }

    public func destinationURL(for item: CatalogItem) -> URL {
        let safeTitle = item.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "|", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var ext = item.downloadURL.pathExtension.lowercased()
        if ext.isEmpty || ext == "php" || ext.count > 5 {
            ext = "mp4"
        }
        return BackdropLibraryService.shared.localWallpapersDirectory
            .appendingPathComponent("\(safeTitle).\(ext)")
    }

    public func downloadAndApply(
        item: CatalogItem,
        target: ApplyTarget = .desktop,
        completion: @escaping (Bool) -> Void
    ) {
        let dest = destinationURL(for: item)

        // Ensure wallpapers directory exists
        let dir = BackdropLibraryService.shared.localWallpapersDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // If already downloaded, just apply it
        if FileManager.default.fileExists(atPath: dest.path) {
            applyDownloaded(item: item, fileURL: dest, target: target)
            completion(true)
            return
        }

        // Fast path for local copy (Backdrop cache)
        if item.isLocalCopy && FileManager.default.fileExists(atPath: item.downloadURL.path) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try FileManager.default.copyItem(at: item.downloadURL, to: dest)
                    DispatchQueue.main.async {
                        self?.applyDownloaded(item: item, fileURL: dest, target: target)
                        completion(true)
                    }
                } catch {
                    print("[WallpaperDownloader] Error copying local file: \(error)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
            return
        }

        // Check if item needs resolving (e.g. MoeWalls page URL)
        if item.downloadURL.absoluteString.contains("moewalls.com") && !item.downloadURL.absoluteString.contains("download.php") {
            downloadStatus[item.id] = "Resolving MoeWalls high-res direct stream..."
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
        var dest = destinationURL(for: taskInfo.item)

        // If suggested filename has mp4/mov and current dest does not
        if let suggested = downloadTask.response?.suggestedFilename,
           (suggested.hasSuffix(".mp4") || suggested.hasSuffix(".mov") || suggested.hasSuffix(".webm")),
           dest.pathExtension.isEmpty || dest.pathExtension == "php" {
            let ext = (suggested as NSString).pathExtension
            dest = dest.deletingPathExtension().appendingPathExtension(ext)
        }

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)

            DispatchQueue.main.async {
                self.downloadProgress.removeValue(forKey: taskInfo.item.id)
                self.downloadStatus.removeValue(forKey: taskInfo.item.id)
                self.applyDownloaded(item: taskInfo.item, fileURL: dest, target: taskInfo.target)
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

    private func applyDownloaded(item: CatalogItem, fileURL: URL, target: ApplyTarget) {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let ext = fileURL.pathExtension.lowercased()
        let isVideo = ["mov", "mp4", "m4v", "webm"].contains(ext)
        let wallpaper = WallpaperItem(
            id: "local-\(item.title)",
            title: item.title,
            type: isVideo ? .video : .image,
            fileURL: fileURL,
            fileSize: Int64(size),
            isCustom: false
        )

        switch target {
        case .desktop:
            WallpaperEngine.shared.setDesktopWallpaper(wallpaper)
        case .lockScreen:
            WallpaperEngine.shared.setLockScreenWallpaper(wallpaper)
        case .both:
            WallpaperEngine.shared.setBothWallpapers(wallpaper)
        }
    }
}
