import Foundation
import XCTest
@testable import ForumIndexCore

@MainActor
final class MarkdownTopicReaderTests: XCTestCase {
    private let url = URL(string: "https://example.com/t/topic/123")!

    func testAppendsPagesWithStableUniqueIDsAndStopsAtLastPage() async {
        let reader = MarkdownTopicReader(url: url, markdown: page("First", next: 2)) { _ in
            Self.document("Second")
        }
        let original = reader.posts[0]
        await reader.loadNextPage()
        XCTAssertEqual(reader.posts.map(\.markdown), ["First", "Second"])
        XCTAssertEqual(reader.posts[0], original)
        XCTAssertEqual(reader.posts.map(\.id), [0, 1])
        XCTAssertNil(reader.nextPageURL)
        XCTAssertFalse(reader.isLoadingMore)
        await reader.loadNextPage()
        XCTAssertEqual(reader.posts.count, 2)
    }

    func testConcurrentRequestsAreCoalescedAndFailureRequiresRetry() async {
        let fetcher = ControlledMarkdownPages()
        let reader = MarkdownTopicReader(url: url, markdown: page("First", next: 2)) { url in
            try await fetcher.fetch(url)
        }
        let request = Task { await reader.loadNextPage() }
        await fetcher.waitForRequest()
        await reader.loadNextPage()
        let requestCount = await fetcher.count
        XCTAssertEqual(requestCount, 1)
        await fetcher.complete(.failure(URLError(.notConnectedToInternet)))
        await request.value
        XCTAssertEqual(reader.posts.map(\.markdown), ["First"])
        XCTAssertNotNil(reader.loadMoreError)
        await reader.loadNextPage()
        let countAfterFailure = await fetcher.count
        XCTAssertEqual(countAfterFailure, 1)
        let retry = Task { await reader.loadNextPage(retrying: true) }
        await fetcher.waitForRequest()
        await fetcher.complete(.success(Self.document("Second")))
        await retry.value
        XCTAssertEqual(reader.posts.count, 2)
        XCTAssertNil(reader.loadMoreError)
    }

    func testCancelledRequestDoesNotAppendOrLoseNextPage() async {
        let fetcher = ControlledMarkdownPages()
        let reader = MarkdownTopicReader(url: url, markdown: page("First", next: 2)) { url in
            try await fetcher.fetch(url)
        }
        let request = Task { await reader.loadNextPage() }
        await fetcher.waitForRequest()
        request.cancel()
        await fetcher.complete(.success(Self.document("Second")))
        await request.value
        XCTAssertEqual(reader.posts.count, 1)
        XCTAssertNotNil(reader.nextPageURL)
        XCTAssertNil(reader.loadMoreError)
        XCTAssertFalse(reader.isLoadingMore)
    }

    func testRepeatedNextLinkEndsPagination() async {
        let reader = MarkdownTopicReader(url: url, markdown: page("First", next: 2)) { _ in
            Self.document("Second") + "\n\n[Next page](https://example.com/t/topic/123.md?page=2)"
        }
        await reader.loadNextPage()
        XCTAssertEqual(reader.posts.count, 2)
        XCTAssertNil(reader.nextPageURL)
    }

    func testFooterNavigationIsRemovedAndRelativeNextURLIsResolved() {
        let markdown = Self.document("Body") + "\n\n[Previous page](/t/topic/123.md?page=1)\n\n[Next page](/t/topic/123.md?page=3)"
        let document = MarkdownTopicDocument(markdown: markdown, baseURL: url)
        XCTAssertEqual(document.posts.first?.markdown, "Body")
        XCTAssertEqual(document.nextPageURL?.absoluteString, "https://example.com/t/topic/123.md?page=3")
    }

    func testNavigationInsideCodeOrOrdinaryPostsIsPreserved() {
        let example = "```\n[Next page](https://example.com/t/topic/123.md?page=2)\n```"
        let document = MarkdownTopicDocument(markdown: Self.document(example), baseURL: url)
        XCTAssertNil(document.nextPageURL)
        XCTAssertEqual(document.posts.first?.markdown, example)
        let ordinary = MarkdownTopicDocument(markdown: "[Next page](https://example.com/t/topic/123.md?page=2)", baseURL: url)
        XCTAssertNil(ordinary.nextPageURL)
    }

    func testOnlyForwardPagesOfTheSameTopicAreFollowed() {
        for candidate in ["https://other.com/t/topic/123.md?page=2", "https://example.com/t/other/456.md?page=2",
                          "https://example.com/t/topic/123.md?page=1", "http://example.com/t/topic/123.md?page=2"] {
            XCTAssertNil(TopicPagination.nextURL(URL(string: candidate), for: url, after: 1))
        }
    }

    func testLoadThresholdIsOneViewportFromTheEnd() {
        XCTAssertFalse(TopicPagination.isNearEnd(contentHeight: 3000, visibleBottom: 1499, viewportHeight: 750))
        XCTAssertFalse(TopicPagination.isNearEnd(contentHeight: 3000, visibleBottom: 2249, viewportHeight: 750))
        XCTAssertTrue(TopicPagination.isNearEnd(contentHeight: 3000, visibleBottom: 2250, viewportHeight: 750))
        XCTAssertTrue(TopicPagination.isNearEnd(contentHeight: 500, visibleBottom: 750, viewportHeight: 750))
        XCTAssertFalse(TopicPagination.isNearEnd(contentHeight: 0, visibleBottom: 0, viewportHeight: 0))
    }

    private func page(_ body: String, next: Int) -> String {
        Self.document(body) + "\n\n[Next page](https://example.com/t/topic/123.md?page=\(next))"
    }

    private nonisolated static func document(_ body: String) -> String {
        "# Topic\n\n**URL:** https://example.com/t/topic/123\n**Page:** 1\n\n\(body)"
    }
}

private actor ControlledMarkdownPages {
    private var pending: CheckedContinuation<String, any Error>?
    private(set) var count = 0

    func fetch(_ url: URL) async throws -> String {
        count += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func waitForRequest() async {
        while pending == nil { await Task.yield() }
    }

    func complete(_ result: Result<String, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }
}
