import Foundation
import XCTest
@testable import ForumIndexCore

@MainActor
final class TopicDocumentCacheTests: XCTestCase {
    private let url = URL(string: "https://example.com/t/topic/1")!

    func testConcurrentReadersShareFetchAndParsedDocument() async throws {
        let cache = TopicDocumentCache()
        let source = Source()
        let url = url
        async let first = cache.load(url: url, fetch: source.fetch)
        async let second = cache.load(url: url, fetch: source.fetch)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.posts.first?.markdown, "Body 1")
        let cached = try await cache.load(url: url, fetch: source.fetch)
        XCTAssertEqual(cached, a)
        let count = await source.count
        XCTAssertEqual(count, 1)
    }

    func testEvictsLeastRecentlyUsedDocument() async throws {
        let cache = TopicDocumentCache(capacity: 2)
        let source = Source()
        let second = url.appendingPathComponent("2")
        let third = url.appendingPathComponent("3")
        _ = try await cache.load(url: url, fetch: source.fetch)
        _ = try await cache.load(url: second, fetch: source.fetch)
        _ = try await cache.load(url: url, fetch: source.fetch)
        _ = try await cache.load(url: third, fetch: source.fetch)
        _ = try await cache.load(url: url, fetch: source.fetch)
        let countBefore = await source.count
        XCTAssertEqual(countBefore, 3)
        _ = try await cache.load(url: second, fetch: source.fetch)
        let countAfter = await source.count
        XCTAssertEqual(countAfter, 4)
    }

    func testExpiredAndOversizedDocumentsAreFetchedAgain() async throws {
        for cache in [TopicDocumentCache(lifetime: 0), TopicDocumentCache(maximumBytes: 1)] {
            let source = Source()
            _ = try await cache.load(url: url, fetch: source.fetch)
            _ = try await cache.load(url: url, fetch: source.fetch)
            let count = await source.count
            XCTAssertEqual(count, 2)
        }
    }

    func testFailureDoesNotPoisonRetry() async throws {
        let cache = TopicDocumentCache()
        do {
            _ = try await cache.load(url: url) { _ in throw URLError(.timedOut) }
            XCTFail("Expected failure")
        } catch { }
        let document = try await cache.load(url: url) { _ in "Recovered" }
        XCTAssertEqual(document.posts.first?.markdown, "Recovered")
    }

    func testCanceledWaiterDoesNotCancelSharedLoad() async throws {
        let cache = TopicDocumentCache()
        let source = Source()
        let url = url
        let canceled = Task { try await cache.load(url: url, fetch: source.fetch) }
        while await source.count == 0 { await Task.yield() }
        canceled.cancel()
        let document = try await cache.load(url: url, fetch: source.fetch)
        XCTAssertEqual(document.posts.first?.markdown, "Body 1")
        do {
            _ = try await canceled.value
            XCTFail("Canceled reader must not receive a document")
        } catch is CancellationError { }
        let count = await source.count
        XCTAssertEqual(count, 1)
    }

    func testAsyncParsingPreservesPaginationAndReaderState() async throws {
        let markdown = "# Topic\n\n**URL:** \(url)\n\nBody\n\n[Next page](?page=2)"
        let document = try await MarkdownTopicDocument.parse(markdown: markdown, baseURL: url)
        XCTAssertEqual(document, MarkdownTopicDocument(markdown: markdown, baseURL: url))
        let reader = MarkdownTopicReader(url: url, document: document)
        XCTAssertEqual(reader.title, "Topic")
        XCTAssertEqual(reader.posts, document.posts)
        XCTAssertEqual(reader.nextPageURL, URL(string: "https://example.com/t/topic/1?page=2"))
    }

    private actor Source {
        var count = 0
        func fetch(_ url: URL) async throws -> String {
            count += 1
            let number = count
            try await Task.sleep(for: .milliseconds(50))
            return "Body \(number)"
        }
    }
}
