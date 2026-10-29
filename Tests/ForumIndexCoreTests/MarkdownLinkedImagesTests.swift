import Foundation
import XCTest
@testable import ForumIndexCore

final class MarkdownLinkedImagesTests: XCTestCase {
    private let baseURL = URL(string: "https://forum.example/t/123")!

    func testRestoresLinkedImageAndKeepsOriginalDestination() throws {
        let text = try parse("Hello 🐳 [![A \\\"quoted\\\" photo](../thumb.png)](/original.png \"A title\")")
        let image = try XCTUnwrap(text.runs.first { $0.imageURL != nil })
        XCTAssertEqual(image.imageURL?.absoluteURL.absoluteString, "https://forum.example/thumb.png")
        XCTAssertEqual(image.link?.absoluteURL.absoluteString, "https://forum.example/original.png")
        XCTAssertTrue(String(text.characters).hasPrefix("Hello 🐳 "))
    }

    func testPreservesOrdinaryImagesLinksAndCode() throws {
        let input = """
        ![Photo](/photo.png)

        [Website](/about)

        `[![Inline code](/thumb.png)](/original.png)`

        ```markdown
        [![Fenced code](/thumb.png)](/original.png)
        ```
        """
        let original = try attributedString(input)
        XCTAssertEqual(try MarkdownLinkedImages.restoringImages(in: original, markdown: input, baseURL: baseURL), original)
    }

    func testKeepsWebpageLinkAndMultipleImagesDistinct() throws {
        let text = try parse("[![One](/one.png)](/about) and [![Two](/two.png)](/two-full.png)")
        let images = text.runs.filter { $0.imageURL != nil }
        XCTAssertEqual(images.map { $0.imageURL?.absoluteURL.path }, ["/one.png", "/two.png"])
        XCTAssertEqual(images.map { $0.link?.absoluteURL.path }, ["/about", "/two-full.png"])
    }

    private func attributedString(_ input: String) throws -> AttributedString {
        try AttributedString(markdown: input, options: .init(appliesSourcePositionAttributes: true), baseURL: baseURL)
    }

    private func parse(_ input: String) throws -> AttributedString {
        try MarkdownLinkedImages.restoringImages(in: attributedString(input), markdown: input, baseURL: baseURL)
    }
}
