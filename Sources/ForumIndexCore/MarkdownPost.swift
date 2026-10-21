import Foundation

public struct MarkdownPost: Equatable, Identifiable, Sendable {
    public let id: Int
    public let username: String?
    public let avatarURL: URL?
    public let publishedAt: Date?
    public let markdown: String
    public var postNumber: Int? = nil
}
