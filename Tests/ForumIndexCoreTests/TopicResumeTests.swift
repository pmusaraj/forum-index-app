import XCTest
@testable import ForumIndexCore

@MainActor
final class TopicResumeTests: XCTestCase {
    private let url = URL(string: "https://example.com/t/long-topic/123")!

    func testSixHundredPostsLocateUnreadWithoutDownloadingEarlierPages() async throws {
        let server = ResumeIndexFixture()
        var bookmark = Bookmark(title: "Long topic", url: url, forumName: "Example")
        bookmark.lastReadPostNumber = 480
        let target = try await TopicResumeClient(fetch: { try await server.fetch($0) }).target(for: bookmark)
        XCTAssertEqual(target.postNumber, 481)
        XCTAssertEqual(target.readThrough, 480)
        XCTAssertEqual(target.pageURL.absoluteString, "https://example.com/t/long-topic/123.md?page=25")
        let requests = await server.requests
        XCTAssertLessThanOrEqual(requests.count, 12)
        XCTAssertFalse(requests.contains { $0.path.hasSuffix(".md") })
    }

    func testDeletedPostNumbersDoNotShiftTheBoundary() async throws {
        let server = ResumeIndexFixture(deleted: [481, 482])
        var bookmark = Bookmark(title: "Long topic", url: url, forumName: "Example")
        bookmark.lastReadPostNumber = 481
        let target = try await TopicResumeClient(fetch: { try await server.fetch($0) }).target(for: bookmark)
        XCTAssertEqual(target.postNumber, 483)
        XCTAssertEqual(target.readThrough, 481)
        XCTAssertEqual(target.pageURL.query, "page=25")
    }

    func testLegacyTimestampMigratesAndCaughtUpStartsAtBeginning() async throws {
        let server = ResumeIndexFixture()
        var bookmark = Bookmark(title: "Long topic", url: url, forumName: "Example")
        bookmark.lastReadAt = Date(timeIntervalSince1970: 480)
        let client = TopicResumeClient(fetch: { try await server.fetch($0) })
        let target = try await client.target(for: bookmark)
        XCTAssertEqual(target.postNumber, 481)
        XCTAssertEqual(target.readThrough, 480)
        bookmark.lastReadAt = Date(timeIntervalSince1970: 1000)
        let caughtUp = try await client.target(for: bookmark)
        XCTAssertNil(caughtUp.postNumber)
        XCTAssertEqual(caughtUp.readThrough, 600)
        XCTAssertEqual(caughtUp.pageURL.query, "page=1")
    }

    func testProgressIsMonotonicAndPartialReadingKeepsUnread() {
        var bookmark = Bookmark(title: "Long topic", url: url, forumName: "Example")
        bookmark.addedAt = Date(timeIntervalSince1970: 100)
        bookmark.lastReadAt = Date(timeIntervalSince1970: 480)
        bookmark.lastReadPostNumber = 480
        bookmark.latestReplyAt = Date(timeIntervalSince1970: 600)
        var data = Bookmark.data(for: [bookmark])
        data = Bookmark.recordingProgress(url: url, postNumber: 481, date: Date(timeIntervalSince1970: 481), in: data)
        XCTAssertTrue(Bookmark.load(from: data)[0].hasUnreadReplies)
        let progress = data
        data = Bookmark.recordingProgress(url: url, postNumber: 400, date: Date(timeIntervalSince1970: 400), in: data)
        XCTAssertEqual(data, progress)
        XCTAssertEqual(Bookmark.load(from: data)[0].lastReadPostNumber, 481)
        data = Bookmark.recordingProgress(url: url, postNumber: 600, date: Date(timeIntervalSince1970: 600), in: data)
        XCTAssertFalse(Bookmark.load(from: data)[0].hasUnreadReplies)
    }

    func testInitialMiddlePageLoadsBothDirectionsWithStablePostIDs() async throws {
        let middle = Self.page(25, numbers: 481...500)
        let reader = MarkdownTopicReader(url: URL(string: "https://example.com/t/long-topic/123.md?page=25")!, markdown: middle) { url in
            if url.query == "page=24" { return Self.page(24, numbers: 461...480) }
            return Self.page(26, numbers: 501...520)
        }
        XCTAssertFalse(reader.startsTopic)
        XCTAssertEqual(reader.posts.first?.postNumber, 481)
        XCTAssertEqual(reader.previousPageURL?.query, "page=24")
        await reader.loadPreviousPage()
        XCTAssertEqual(reader.posts.first?.id, 461)
        XCTAssertEqual(reader.posts.last?.id, 500)
        await reader.loadNextPage()
        XCTAssertEqual(reader.posts.last?.id, 520)
        XCTAssertEqual(Set(reader.posts.map(\.id)).count, 60)
        XCTAssertFalse(reader.hasCompleteTopic)
    }

    func testEarlierFailurePreservesPostsAndCanRetry() async {
        let server = EarlierPageFixture()
        let reader = MarkdownTopicReader(url: URL(string: "https://example.com/t/long-topic/123.md?page=25")!,
                                         markdown: Self.page(25, numbers: 481...500)) { _ in try await server.fetch() }
        await reader.loadPreviousPage()
        XCTAssertNotNil(reader.loadPreviousError)
        XCTAssertEqual(reader.posts.first?.id, 481)
        await reader.loadPreviousPage()
        let count = await server.count
        XCTAssertEqual(count, 1)
        await reader.loadPreviousPage(retrying: true)
        XCTAssertNil(reader.loadPreviousError)
        XCTAssertEqual(reader.posts.first?.id, 461)
    }

    nonisolated static func page(_ page: Int, numbers: ClosedRange<Int>) -> String {
        var result = "# Long topic\n\n**URL:** https://example.com/t/long-topic/123\n**Page:** \(page)\n\n"
        result += numbers.map { number in
            "<div class=\"post-metadata\">\n**Author:** [@author-\(number)](https://example.com/u/author)\n**Post date:** [Date](https://example.com/t/long-topic/123/\(number) \"1970-01-01T00:08:01Z\")\n</div>\n\nReply \(number)."
        }.joined(separator: "\n\n---\n\n")
        if page > 1 { result += "\n\n[Previous page](https://example.com/t/long-topic/123.md?page=\(page - 1))" }
        result += "\n\n[Next page](https://example.com/t/long-topic/123.md?page=\(page + 1))"
        return result
    }
}

private actor ResumeIndexFixture {
    var requests: [URL] = []
    let deleted: Set<Int>
    init(deleted: Set<Int> = []) { self.deleted = deleted }

    func fetch(_ url: URL) throws -> Data {
        requests.append(url)
        let numbers = (1...600).filter { !deleted.contains($0) }
        let formatter = ISO8601DateFormatter()
        func post(_ number: Int) -> [String: Any] {
            ["id": number + 1000, "post_number": number,
             "created_at": formatter.string(from: Date(timeIntervalSince1970: Double(number)))]
        }
        if url.path.hasSuffix("/posts.json") {
            let id = Int(URLComponents(url: url, resolvingAgainstBaseURL: true)!.queryItems![0].value!)!
            return try JSONSerialization.data(withJSONObject: ["post_stream": ["posts": [post(id - 1000)]]])
        }
        return try JSONSerialization.data(withJSONObject: [
            "post_stream": ["stream": numbers.map { $0 + 1000 }, "posts": numbers.prefix(20).map(post)],
            "chunk_size": 20, "last_posted_at": formatter.string(from: Date(timeIntervalSince1970: 600))
        ])
    }
}

private actor EarlierPageFixture {
    var count = 0
    func fetch() throws -> String {
        count += 1
        if count == 1 { throw URLError(.notConnectedToInternet) }
        return TopicResumeTests.page(24, numbers: 461...480)
    }
}
