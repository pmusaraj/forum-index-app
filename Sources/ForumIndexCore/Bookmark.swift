import Foundation

public struct Bookmark: Codable, Identifiable, Sendable {
    public let title: String
    public let url: URL
    public let forumName: String
    public let topicID: Int?
    public let topic: Topic?

    public var addedAt: Date?
    public var lastReadAt: Date?
    public var latestReplyAt: Date?
    public var lastReadPostNumber: Int?

    public var hasUnreadReplies: Bool {
        guard let latestReplyAt, let baseline = lastReadAt ?? addedAt else { return false }
        return latestReplyAt > baseline
    }

    public init(title: String, url: URL, forumName: String, topicID: Int? = nil, topic: Topic? = nil) {
        self.title = title
        self.url = url
        self.forumName = forumName
        self.topicID = topicID
        self.topic = topic
        self.addedAt = Date()
    }

    public var id: String { url.absoluteString }

    public static func load(from data: Data) -> [Bookmark] {
        var saved = (try? JSONDecoder().decode([Bookmark].self, from: data)) ?? []
        // Legacy arrays were stored oldest first. Preserve that order during migration.
        let migrationDate = Date()
        for index in saved.indices where saved[index].addedAt == nil {
            saved[index].addedAt = migrationDate.addingTimeInterval(-Double(saved.count - index))
            saved[index].lastReadAt = migrationDate
        }
        return saved.enumerated().sorted {
            let lhs = $0.element.addedAt ?? .distantPast
            let rhs = $1.element.addedAt ?? .distantPast
            return lhs == rhs ? $0.offset > $1.offset : lhs > rhs
        }.map(\.element)
    }

    public static func data(for bookmarks: [Bookmark]) -> Data {
        (try? JSONEncoder().encode(bookmarks)) ?? Data()
    }

    public static func toggling(_ bookmark: Bookmark, in data: Data) -> Data {
        var bookmarks = load(from: data)
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks.remove(at: index)
        } else {
            var added = bookmark
            added.addedAt = Date()
            added.lastReadAt = added.addedAt
            added.latestReplyAt = nil
            bookmarks.append(added)
        }
        return self.data(for: bookmarks)
    }
}

extension Bookmark {
    public static let replyCheckInterval: TimeInterval = 300
    public static let replyCheckLimit = 20

    /// Only the newest 20 saves are tracked. Skipped entries do not admit older bookmarks.
    public static func replyCheckCandidates(in data: Data) -> [Bookmark] {
        load(from: data)
            .prefix(replyCheckLimit)
            .filter { !$0.hasUnreadReplies && BookmarkReplyClient.endpoint(for: $0.url) != nil }
    }

    /// Opening a Markdown topic does not imply reading its replies.
    public static func opening(_ bookmark: Bookmark, in data: Data) -> Data {
        bookmark.topic?.usesMarkdownReader == true ? data : markingRead(url: bookmark.url, in: data)
    }

    public static func recordingProgress(url: URL, postNumber: Int?, date: Date?, in data: Data) -> Data {
        var bookmarks = load(from: data)
        guard let index = bookmarks.firstIndex(where: { $0.url == url }) else { return data }
        var changed = false
        let baseline = bookmarks[index].lastReadAt ?? bookmarks[index].addedAt ?? .distantPast
        let canAdvanceCursor = bookmarks[index].lastReadPostNumber != nil || date == nil
            || date.map { $0 > baseline } == true
        if let postNumber, canAdvanceCursor, postNumber > (bookmarks[index].lastReadPostNumber ?? 0) {
            bookmarks[index].lastReadPostNumber = postNumber
            changed = true
        }
        if let date, date > (bookmarks[index].lastReadAt ?? bookmarks[index].addedAt ?? .distantPast) {
            bookmarks[index].lastReadAt = date
            changed = true
        }
        return changed ? self.data(for: bookmarks) : data
    }

    public static func recordingActivity(url: URL, date: Date?, in data: Data) -> Data {
        var bookmarks = load(from: data)
        guard let index = bookmarks.firstIndex(where: { $0.url == url }), let date,
              date > (bookmarks[index].latestReplyAt ?? .distantPast) else { return data }
        bookmarks[index].latestReplyAt = date
        return self.data(for: bookmarks)
    }

    public static func markingRead(url: URL, in data: Data, at date: Date = Date()) -> Data {
        var bookmarks = load(from: data)
        guard let index = bookmarks.firstIndex(where: { $0.url == url }) else { return data }
        bookmarks[index].lastReadAt = date
        return self.data(for: bookmarks)
    }
}
