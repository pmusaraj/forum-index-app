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

    private func response(status: Int = 200, contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com/t/123")!, statusCode: status,
                        httpVersion: nil, headerFields: ["Content-Type": contentType])!
    }
}
