import Foundation
import XCTest
@testable import ForumIndexCore

final class MarkdownTopicDocumentTests: XCTestCase {
    func testSummaryIsSeparatedFromPostsAndPreservesMarkdown() {
        let summary = "An **overview**.\n\n## Details\n\n[Reference][source]\n\n[source]: https://example.com\n\n---"
        let document = MarkdownTopicDocument(markdown: summaryDocument(summary))
        XCTAssertEqual(document.summary, summary)
        XCTAssertEqual(document.posts.map(\.markdown), ["Original post."])
        XCTAssertEqual(document.posts.map(\.id), [0])
        XCTAssertTrue(document.startsTopic)
    }

    func testSummaryHeadingInPostsCodeAndOrdinaryMarkdownIsNotExtracted() {
        let heading = "## AI-generated summary\n\nWritten by a person."
        let ordinary = MarkdownTopicDocument(markdown: heading)
        XCTAssertNil(ordinary.summary)
        XCTAssertEqual(ordinary.posts.first?.markdown, heading)
        let post = MarkdownTopicDocument(markdown: summaryDocument("Overview.")
            .replacingOccurrences(of: "Original post.", with: heading))
        XCTAssertEqual(post.posts.first?.markdown, heading)
        let code = MarkdownTopicDocument(markdown: summaryDocument("Overview.")
            .replacingOccurrences(of: "## AI-generated summary\n\nOverview.",
                                  with: "```markdown\n\(heading)\n```"))
        XCTAssertNil(code.summary)
        XCTAssertTrue(code.posts.first?.markdown.contains(heading) == true)
    }

    func testEmptyOrUnboundedSummaryDoesNotCreateSummaryControl() {
        XCTAssertNil(MarkdownTopicDocument(markdown: summaryDocument("")).summary)
        XCTAssertEqual(MarkdownTopicDocument(markdown: summaryDocument("")).posts.count, 1)
        let unbounded = "# Topic\n\n**URL:** https://example.com/t/123\n\n## AI-generated summary\n\nKeep this."
        XCTAssertNil(MarkdownTopicDocument(markdown: unbounded).summary)
        XCTAssertTrue(MarkdownTopicDocument(markdown: unbounded).posts[0].markdown.contains("Keep this."))
    }

    func testPartialTopicDocumentsAreNotTreatedAsCompleteTopicStarts() {
        for field in ["**Page:** 2", "**Showing post:** 7"] {
            let document = MarkdownTopicDocument(markdown: summaryDocument("Overview.")
                .replacingOccurrences(of: "**Page:** 1", with: field))
            XCTAssertFalse(document.startsTopic)
            XCTAssertNil(document.summary)
        }
    }

    private func summaryDocument(_ summary: String) -> String {
        """
        # Topic

        **URL:** https://example.com/t/123
        **Page:** 1

        ## AI-generated summary

        \(summary)

        <div class="post-metadata">
        **Author:** [@alice](https://example.com/u/alice)
        </div>

        Original post.
        """
    }

    func testLegacyMarkdownPluginProducesStructuredPosts() throws {
        let document = MarkdownTopicDocument(markdown: """
        # Legacy topic

        **URL:** https://discuss.privacyguides.net/t/example/123
        **Category:** Questions
        **Created:** 2026-09-23T17:00:56Z
        **Posts:** 2

        ## Post 1 by @ZenByte — 2026-09-23T17:00:56Z

        Hello **world**.

        ---

        ## Post 2 by @privacy.slouchy — 2026-09-24T17:05:32.123Z

        > A quote

        **Posts:** 99
        """, postIDOffset: 10)

        XCTAssertEqual(document.title, "Legacy topic")
        XCTAssertEqual(document.posts.count, 2)
        let first = try XCTUnwrap(document.posts.first)
        XCTAssertEqual(first.id, 10)
        XCTAssertEqual(first.username, "ZenByte")
        XCTAssertNil(first.avatarURL)
        XCTAssertEqual(first.publishedAt, ISO8601DateFormatter().date(from: "2026-09-23T17:00:56Z"))
        XCTAssertEqual(first.markdown, "Hello **world**.")
        let second = document.posts[1]
        XCTAssertEqual(second.id, 11)
        XCTAssertEqual(second.username, "privacy.slouchy")
        XCTAssertNotNil(second.publishedAt)
        XCTAssertEqual(second.markdown, "> A quote\n\n**Posts:** 99")
    }

    func testLegacyMarkdownHeadingsInCodeAndMalformedHeadingsArePreserved() {
        let body = """
        ```markdown
        ## Post 2 by @example — 2026-09-23T17:00:56Z
        ```

        ## Post 3 by @example — invalid-date
        """
        let document = MarkdownTopicDocument(markdown: """
        # Legacy topic

        **URL:** https://example.com/t/123
        **Posts:** 1

        ## Post 1 by @alice — 2026-09-23T17:00:56Z

        \(body)
        """)
        XCTAssertEqual(document.posts.count, 1)
        XCTAssertEqual(document.posts.first?.markdown, body)

        let ordinary = "## Post 1 by @alice — 2026-09-23T17:00:56Z\n\n**Posts:** 1"
        XCTAssertEqual(MarkdownTopicDocument(markdown: ordinary).posts.first?.markdown, ordinary)
        XCTAssertNil(MarkdownTopicDocument(markdown: ordinary).posts.first?.username)
    }

    func testDiscourseEnvelopeAndAuthorMetadataBecomeStructuredPosts() throws {
        let markdown = """
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
        """

        // Current Discourse uses bold labels and Markdown hard line breaks.
        let currentMarkdown = markdown
            .replacingOccurrences(of: "### Author:", with: "**Author:**")
            .replacingOccurrences(of: "#### Post date:", with: "**Post date:**")
            .components(separatedBy: "\n")
            .map { $0.hasPrefix("**") && !$0.hasPrefix("**Post date:**") && !$0.hasPrefix("**Page:**") ? $0 + "\\" : $0 }
            .joined(separator: "\n")
        XCTAssertEqual(MarkdownTopicDocument(markdown: currentMarkdown), MarkdownTopicDocument(markdown: markdown))
        for input in [markdown, currentMarkdown] {
            let document = MarkdownTopicDocument(markdown: input)
            XCTAssertEqual(document.title, "A topic")
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
    }

    func testLinkedPostEnvelopeProvidesTitleAndHidesShowingPostField() {
        let document = MarkdownTopicDocument(markdown: """
        # Linked topic

        **URL:** https://example.com/t/linked/12
        **Posts on this page:** 1
        **Showing post:** 7

        <div class="post-metadata">
        ### Author: [@alice](https://example.com/u/alice)
        </div>

        The linked reply.
        """)
        XCTAssertEqual(document.title, "Linked topic")
        XCTAssertEqual(document.posts.count, 1)
        XCTAssertEqual(document.posts.first?.markdown, "The linked reply.")
        XCTAssertEqual(document.posts.first?.username, "alice")
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
        XCTAssertNil(document.title)
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
