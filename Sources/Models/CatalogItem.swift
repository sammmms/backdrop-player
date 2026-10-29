import Foundation

public struct CatalogItem: Identifiable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let category: String
    public let thumbnailURL: URL?
    public let previewURL: URL?
    public let downloadURL: URL
    public let resolution: String
    public let fileSizeString: String
    public let sourceDescription: String
    public let isLocalCopy: Bool

    public init(
        id: String,
        title: String,
        category: String,
        thumbnailURL: URL? = nil,
        previewURL: URL? = nil,
        downloadURL: URL,
        resolution: String = "4K",
        fileSizeString: String = "40 MB",
        sourceDescription: String = "Online",
        isLocalCopy: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.thumbnailURL = thumbnailURL
        self.previewURL = previewURL
        self.downloadURL = downloadURL
        self.resolution = resolution
        self.fileSizeString = fileSizeString
        self.sourceDescription = sourceDescription
        self.isLocalCopy = isLocalCopy
    }
}
