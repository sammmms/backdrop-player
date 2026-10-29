import Foundation

public struct WallpaperItem: Identifiable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let type: WallpaperType
    public let fileURL: URL
    public let fileSize: Int64
    public let isCustom: Bool

    public enum WallpaperType: String, Codable {
        case video
        case image
        case unknown
    }

    public init(
        id: String,
        title: String,
        type: WallpaperType,
        fileURL: URL,
        fileSize: Int64,
        isCustom: Bool = false
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.isCustom = isCustom
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}
