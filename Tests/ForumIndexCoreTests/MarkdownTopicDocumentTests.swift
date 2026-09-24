import Foundation
import XCTest
@testable import ForumIndexCore

final class MarkdownTopicDocumentTests: XCTestCase {
    func testDiscourseEnvelopeAndAuthorMetadataBecomeStructuredPosts() throws {
        let document = MarkdownTopicDocument(markdown: """
        # A topic

        **URL:** https://example.com/t/123
        **Category:** Feedback
        **Tags:** ai, content-localization
        **Created:** yesterday
        **Posts on this page:** 2
        **Page:** 1

        <div class="post-metadata">

        ### Author: ![Alice](https://example.com/alice.png) [@alice](https://example.com/u/alice)
        #### Post date: [Yesterday](https://example.com/t/123/1 "2026-09-20T19:27:15Z")

        </div>

        Hello **world**.

        ---

        <div class="post-metadata">

        ### Author: ![Bob](https://example.com/bob.png) [@bob](https://example.com/u/bob)
        #### Post date: [Today](https://example.com/t/123/2 "2026-09-21T19:27:15.434Z")

        </div>

        > A quote

        My reply.
        """)
        XCTAssertEqual(document.posts.count, 2)
        let first = try XCTUnwrap(document.posts.first)
        XCTAssertEqual(first.username, "alice")
        XCTAssertEqual(first.avatarURL?.absoluteString, "https://example.com/alice.png")
        XCTAssertNotNil(first.publishedAt)
        XCTAssertEqual(first.markdown, "Hello **world**.")
        XCTAssertEqual(document.posts[1].username, "bob")
        XCTAssertNotNil(document.posts[1].publishedAt)
        XCTAssertEqual(document.posts[1].markdown, "> A quote\n\nMy reply.")
    }

    func testOrdinaryMarkdownAndCodeExamplesArePreserved() {
        let markdown = """
        # My own heading

        ```html
        <div class="post-metadata">
        ### Author: [@sample](https://example.com/u/sample)
        </div>
        ```

        **Category:** This belongs to the post.
        **Tags:** This also belongs to the post.
        """
        let document = MarkdownTopicDocument(markdown: markdown)
        XCTAssertEqual(document.posts.count, 1)
        XCTAssertEqual(document.posts.first?.markdown, markdown)
        XCTAssertNil(document.posts.first?.username)
    }

    func testMalformedMetadataDoesNotDiscardPostContent() {
        let markdown = "<div class=\"post-metadata\">\nAn unexpected format\n</div>\n\nKeep me."
        XCTAssertEqual(MarkdownTopicDocument(markdown: markdown).posts.first?.markdown, markdown)
    }

    func testMissingDateAndInvalidAvatarStillPreserveAuthorAndBody() {
        let markdown = """
        <div class='post-metadata'>
        ### Author: ![A](javascript:alert) [@alice](https://example.com/u/alice)
        </div>

        Body.
        """
        let post = MarkdownTopicDocument(markdown: markdown).posts.first
        XCTAssertEqual(post?.username, "alice")
        XCTAssertNil(post?.avatarURL)
        XCTAssertNil(post?.publishedAt)
        XCTAssertEqual(post?.markdown, "Body.")
    }

    func testRelativeDatesUseSmallUnitsAndDaysInsteadOfWeeks() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        for (seconds, label) in [(0, "Just now"), (60, "1 minute ago"), (120, "2 minutes ago"),
                                  (3600, "1 hour ago"), (7200, "2 hours ago"),
                                  (86400, "1 day ago"), (864000, "10 days ago")] {
            XCTAssertEqual(PostRelativeDate.label(for: now.addingTimeInterval(-Double(seconds)), now: now), label)
        }
    }
}
