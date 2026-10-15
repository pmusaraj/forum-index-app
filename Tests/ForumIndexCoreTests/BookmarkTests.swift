import XCTest
@testable import ForumIndexCore

final class BookmarkTests: XCTestCase {
    private func bookmark(_ id: Int) -> Bookmark {
        Bookmark(title: "Topic \(id)", url: URL(string: "https://example.com/t/topic/\(id)")!, forumName: "Forum")
    }

    func testNewestFirstAndReaddingMovesToTop() {
        var first = bookmark(1)
        first.addedAt = Date(timeIntervalSince1970: 1)
        var second = bookmark(2)
        second.addedAt = Date(timeIntervalSince1970: 2)
        var data = Bookmark.data(for: [first, second])
        XCTAssertEqual(Bookmark.load(from: data).map(\.id), [second.id, first.id])
        data = Bookmark.toggling(first, in: data)
        data = Bookmark.toggling(first, in: data)
        XCTAssertEqual(Bookmark.load(from: data).map(\.id), [first.id, second.id])
    }

    func testLegacyBookmarksPreserveReverseInsertionOrderAcrossPersistence() throws {
        let objects = [1, 2, 3].map { ["title": "Topic", "url": "https://example.com/t/\($0)", "forumName": "Forum"] }
        let data = try JSONSerialization.data(withJSONObject: objects)
        let migrated = Bookmark.load(from: data)
        XCTAssertEqual(migrated.map(\.url.lastPathComponent), ["3", "2", "1"])
        XCTAssertFalse(migrated.contains { $0.hasUnreadReplies })
        XCTAssertEqual(Bookmark.load(from: Bookmark.data(for: migrated)).map(\.id), migrated.map(\.id))
    }

    func testReadClearsDotAndLaterReplyRestoresIt() {
        var saved = bookmark(1)
        saved.addedAt = Date(timeIntervalSince1970: 10)
        saved.latestReplyAt = Date(timeIntervalSince1970: 20)
        XCTAssertTrue(saved.hasUnreadReplies)
        let data = Bookmark.markingRead(url: saved.url, in: Bookmark.data(for: [saved]), at: Date(timeIntervalSince1970: 30))
        saved = Bookmark.load(from: data)[0]
        XCTAssertFalse(saved.hasUnreadReplies)
        // A late response containing activity from before the read must not restore the dot.
        saved.latestReplyAt = Date(timeIntervalSince1970: 25)
        XCTAssertFalse(saved.hasUnreadReplies)
        saved.latestReplyAt = Date(timeIntervalSince1970: 40)
        XCTAssertTrue(saved.hasUnreadReplies)
    }

    func testReplyChecksOnlyTrackTheNewestTwentyBookmarks() {
        var bookmarks = (1...45).map { id in
            var saved = bookmark(id)
            saved.addedAt = Date(timeIntervalSince1970: Double(id))
            return saved
        }
        let candidates = Bookmark.replyCheckCandidates(in: Bookmark.data(for: bookmarks))
        XCTAssertEqual(candidates.map(\.id), bookmarks.suffix(20).reversed().map(\.id))
        // Unread recent saves must not cause older saves to enter the tracked set.
        bookmarks[44].latestReplyAt = Date(timeIntervalSince1970: 100)
        let next = Bookmark.replyCheckCandidates(in: Bookmark.data(for: bookmarks))
        XCTAssertEqual(next.count, 19)
        XCTAssertEqual(next.map(\.id), bookmarks[25..<44].reversed().map(\.id))
    }

    func testReplyChecksSkipUnreadAndUnsupportedBookmarksUntilRead() {
        var unread = bookmark(1)
        unread.addedAt = Date(timeIntervalSince1970: 10)
        unread.latestReplyAt = Date(timeIntervalSince1970: 20)
        let unsupported = Bookmark(title: "Other", url: URL(string: "https://example.com/about")!, forumName: "Forum")
        let data = Bookmark.data(for: [unread, unsupported])
        XCTAssertTrue(Bookmark.replyCheckCandidates(in: data).isEmpty)
        let read = Bookmark.markingRead(url: unread.url, in: data, at: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(Bookmark.replyCheckCandidates(in: read).map(\.id), [unread.id])
    }

    func testMetadataEndpointRemovesPostNumberAndPreservesForumSubpath() {
        XCTAssertEqual(BookmarkReplyClient.endpoint(for: URL(string: "https://example.com/forum/t/a-topic/123/45?foo=bar#post")!)?.absoluteString,
                       "https://example.com/forum/t/123.json")
        XCTAssertEqual(BookmarkReplyClient.endpoint(for: URL(string: "https://example.com/t/123")!)?.absoluteString,
                       "https://example.com/t/123.json")
        XCTAssertNil(BookmarkReplyClient.endpoint(for: URL(string: "https://example.com/about")!))
        XCTAssertNil(BookmarkReplyClient.endpoint(for: URL(string: "http://example.com/t/123")!))
    }
}
