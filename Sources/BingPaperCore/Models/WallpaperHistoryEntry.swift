import Foundation

public struct WallpaperHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let metadata: BingImageMetadata
    public let market: String
    public let localPath: String
    public let downloadedAt: Date
    public var lastAppliedAt: Date?

    public var fileURL: URL {
        URL(fileURLWithPath: localPath)
    }

    public init(
        metadata: BingImageMetadata,
        market: String,
        localPath: String,
        downloadedAt: Date = Date(),
        lastAppliedAt: Date? = nil
    ) {
        self.id = "\(metadata.startdate)-\(market)-\(metadata.hsh ?? metadata.urlbase)"
        self.metadata = metadata
        self.market = market
        self.localPath = localPath
        self.downloadedAt = downloadedAt
        self.lastAppliedAt = lastAppliedAt
    }
}
