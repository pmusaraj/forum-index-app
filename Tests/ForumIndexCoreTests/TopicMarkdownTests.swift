import Foundation
import XCTest
@testable import ForumIndexCore

final class TopicMarkdownTests: XCTestCase {
    func testForumCapabilityDefaultsAndRoundTrips() throws {
        for (field, expected) in [("", false), (",\"supports_markdown\":null", false),
                                  (",\"supports_markdown\":false", false), (",\"supports_markdown\":true", true)] {
            let json = "{\"id\":1,\"name\":\"Forum\",\"slug\":\"forum\"\(field)}"
            let forum = try JSONDecoder().decode(ForumSummary.self, from: Data(json.utf8))
            XCTAssertEqual(forum.supportsMarkdown, expected)
            XCTAssertEqual(try JSONDecoder().decode(ForumSummary.self, from: JSONEncoder().encode(forum)), forum)
        }
    }

    func testRequestsMarkdownFromOriginalTopicURLWithoutAPICredentials() throws {
        let url = URL(string: "https://example.com/t/topic/123")!
        let request = try TopicMarkdownClient.request(for: url)
        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/markdown")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try TopicMarkdownClient.request(for: URL(string: "http://example.com/t/123")!))
    }

    func testAcceptsMarkdownWithCharset() throws {
        let markdown = "# Topic\n\nSome **formatted** content."
        XCTAssertEqual(try TopicMarkdownClient.decode(
            data: Data(markdown.utf8), response: response(contentType: "text/markdown; charset=utf-8")
        ), markdown)
    }

    func testRejectsResponsesThatShouldFallBackToWebView() {
        for (status, type, body) in [
            (200, "text/html", "<html>Sign in</html>"),
            (200, "text/plain", "Not Markdown"),
            (403, "text/markdown", "Access denied"),
            (500, "text/markdown", "Server error"),
            (429, "text/markdown", "Rate limited"),
            (503, "text/markdown", "Conversion unavailable"),
            (200, "text/markdown", " \n\t")
        ] {
            XCTAssertThrowsError(try TopicMarkdownClient.decode(
                data: Data(body.utf8), response: response(status: status, contentType: type)
            ))
        }
        XCTAssertThrowsError(try TopicMarkdownClient.decode(
            data: Data([0xff]), response: response(contentType: "text/markdown")
        ))
    }

    func testReaderSourceDistinguishesMissingNullAndConvertedAndPersistsBookmarks() throws {
        let original = URL(string: "https://example.com/t/topic/123")!
        let converted = URL(string: "https://reader.example/api/topics/123/markdown")!
        for native in [false, true] {
            for (field, expected) in [
                ("", native ? original : nil),
                (",\"reader_markdown_url\":null", nil),
                (",\"reader_markdown_url\":\"\(converted.absoluteString)\"", converted),
                (",\"reader_markdown_url\":\"http://unsafe.example/topic\"", nil)
            ] {
                let json = """
                {"id":123,"title":"Topic","url":"\(original)","forum":{"id":1,"name":"Forum","slug":"forum","supports_markdown":\(native)}\(field)}
                """
                let topic = try JSONDecoder().decode(Topic.self, from: Data(json.utf8))
                XCTAssertEqual(topic.readerMarkdownURL, expected)
                XCTAssertEqual(topic.usesMarkdownReader, expected != nil)
                let bookmark = Bookmark(title: topic.title, url: original, forumName: "Forum", topic: topic)
                let data = Bookmark.data(for: [bookmark])
                let restored = try XCTUnwrap(Bookmark.load(from: data).first)
                XCTAssertEqual(restored.url, original)
                XCTAssertEqual(restored.topic, topic)
                if expected != nil {
                    XCTAssertEqual(Bookmark.opening(restored, in: data), data)
                    let progress = Bookmark.recordingProgress(url: original, postNumber: 73, date: nil, in: data)
                    XCTAssertEqual(Bookmark.load(from: progress).first?.lastReadPostNumber, 73)
                }
            }
        }
    }

    func testOriginalResumeUsesUpstreamPostNumberNotPageNumber() {
        let target = TopicResumeClient.Target(pageURL: URL(string: "https://example.com/t/topic/123.md?page=2")!,
                                             postNumber: 73, readThrough: 68, latestReplyAt: nil)
        XCTAssertEqual(TopicResumeClient.originalURL(for: target, topicURL: URL(string: "https://example.com/t/topic/123/5?foo=bar")!)
            .absoluteString, "https://example.com/t/topic/123/73")
    }

    func testRetryAfterBlocksRequestsAcrossClientsAndPages() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RateLimitedMarkdownProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://\(UUID().uuidString.lowercased()).example/markdown")!
        for destination in [url, url.appending(queryItems: [URLQueryItem(name: "page", value: "2")])] {
            do {
                _ = try await TopicMarkdownClient(session: session).fetch(url: destination)
                XCTFail("Rate limited requests must fail")
            } catch {}
        }
        XCTAssertEqual(RateLimitedMarkdownProtocol.requestCount(for: url.host!), 1)
    }

    func testRetryAfterSupportsSecondsAndHTTPDate() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(TopicMarkdownClient.retryDate("120", now: now), now.addingTimeInterval(120))
        XCTAssertEqual(TopicMarkdownClient.retryDate("Thu, 01 Jan 1970 00:02:00 GMT", now: now), now.addingTimeInterval(120))
        XCTAssertNil(TopicMarkdownClient.retryDate("invalid", now: now))
        XCTAssertNil(TopicMarkdownClient.retryDate("-1", now: now))
    }

    private func response(status: Int = 200, contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com/t/123")!, statusCode: status,
                        httpVersion: nil, headerFields: ["Content-Type": contentType])!
    }
}

private final class RateLimitedMarkdownProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var counts: [String: Int] = [:]

    static func requestCount(for host: String) -> Int {
        lock.withLock { counts[host, default: 0] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.counts[request.url!.host!, default: 0] += 1 }
        let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                       headerFields: ["Retry-After": "120", "Content-Type": "text/markdown"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("Unavailable".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
