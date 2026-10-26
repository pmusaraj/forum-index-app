import Foundation
import XCTest
@testable import ForumIndexCore

final class MarkdownOneboxTests: XCTestCase {
    func testGitHubExportRestoresFormattingAndPreservesSurroundingText() throws {
        let markdown = ###"""
        Before **the preview**.

        > <https://github.com/openai/codex/issues/57084>
        >
        > \## Summary
        >
        > Recurring \*\*errors\*\* with \`code\`.
        >
        > \- \[Evidence\](https://example.com)
        >
        > \`\`\`text
        > logs
        > \`\`\`

        After the preview.
        """###
        let segments = MarkdownOnebox.segments(in: markdown)
        XCTAssertEqual(segments.count, 3)
        XCTAssertFalse(segments[0].isOnebox)
        XCTAssertEqual(segments[0].markdown, "Before **the preview**.\n")
        XCTAssertTrue(segments[1].isOnebox)
        XCTAssertTrue(segments[1].markdown.contains("## Summary"))
        XCTAssertTrue(segments[1].markdown.contains("**errors** with `code`"))
        XCTAssertTrue(segments[1].markdown.contains("- [Evidence](https://example.com)"))
        XCTAssertTrue(segments[1].markdown.contains("```text\nlogs\n```"))
        let rendered = try AttributedString(markdown: segments[1].markdown)
        XCTAssertTrue(rendered.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(rendered.runs.contains { $0.link?.absoluteString == "https://example.com" })
        XCTAssertEqual(segments[2].markdown, "\nAfter the preview.")
    }

    func testOrdinaryQuotesCodeAndNonGitHubEscapesArePreserved() {
        for markdown in [
            "> Quoted \\*\\*literal text\\*\\*",
            ">> <https://github.com/openai/codex/issues/1>\n>>\n>> text",
            "```markdown\n> <https://github.com/openai/codex/issues/1>\n>\n> \\## Heading\n```",
            "~~~~markdown\n> <https://github.com/openai/codex/issues/1>\n>\n> text\n~~~~",
            "    > <https://github.com/openai/codex/issues/1>\n    >\n    > text"
        ] {
            XCTAssertEqual(MarkdownOnebox.segments(in: markdown).map(\.markdown), [markdown])
            XCTAssertFalse(MarkdownOnebox.segments(in: markdown)[0].isOnebox)
        }
        let other = MarkdownOnebox.segments(in: "> <https://example.com/article>\n>\n> Literal \\*asterisk\\*")
        XCTAssertTrue(other[0].isOnebox)
        XCTAssertTrue(other[0].markdown.contains("\\*asterisk\\*"))
    }

    func testMultipleOneboxesHaveStableDistinctIDs() {
        let markdown = "> <https://github.com/a/b>\n>\n> Short\n\n> <https://example.com>\n>\n> Second"
        let segments = MarkdownOnebox.segments(in: markdown)
        XCTAssertEqual(segments.filter(\.isOnebox).count, 2)
        XCTAssertEqual(Set(segments.map(\.id)).count, segments.count)
        XCTAssertEqual(segments, MarkdownOnebox.segments(in: markdown))
    }
}
