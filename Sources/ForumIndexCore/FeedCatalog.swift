import Foundation

public struct FeedCatalog: Codable, Equatable, Sendable {
    public let version: String
    public let feeds: [DiscoveredFeed]

    public init(version: String = "v2", feeds: [DiscoveredFeed]) {
        self.version = version
        self.feeds = feeds
    }
}

