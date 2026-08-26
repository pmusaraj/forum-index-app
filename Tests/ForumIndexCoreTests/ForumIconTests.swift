import XCTest
@testable import ForumIndexCore

final class ForumIconTests: XCTestCase {
    func testDecodesStoredForumIconURL() throws {
        let json = #"{"id":2,"name":"Forum","slug":"forum","base_url":"https://example.com/community","icon_url":"https://cdn.example.com/icon.png"}"#

        let forum = try JSONDecoder().decode(ForumSummary.self, from: Data(json.utf8))

        XCTAssertEqual(forum.iconURL?.absoluteString, "https://cdn.example.com/icon.png")
        XCTAssertEqual(ForumPresentation.iconURL(for: forum)?.absoluteString, "https://cdn.example.com/icon.png")
    }

    func testMissingOrUnsafeBackendIconDoesNotSynthesizeAnOriginFavicon() throws {
        let missing = ForumSummary(
            id: 1,
            name: "Forum",
            slug: "forum",
            baseURL: URL(string: "https://example.com/community"),
            iconURL: nil
        )
        let unsafeJSON = #"{"id":2,"name":"Forum","slug":"forum","base_url":"https://example.com/community","icon_url":"http://cdn.example.com/icon.png"}"#
        let unsafe = try JSONDecoder().decode(ForumSummary.self, from: Data(unsafeJSON.utf8))

        XCTAssertNil(ForumPresentation.iconURL(for: missing))
        XCTAssertNil(unsafe.iconURL)
        XCTAssertNil(ForumPresentation.iconURL(for: unsafe))
    }
}
