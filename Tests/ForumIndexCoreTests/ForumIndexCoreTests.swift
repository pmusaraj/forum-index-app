import XCTest
@testable import ForumIndexCore

final class ForumIndexCoreTests: XCTestCase {
    func testNormalizesForumName() {
        XCTAssertEqual(
            ForumIndexCore.normalizedForumName("  Swift Forums\n"),
            "Swift Forums"
        )
    }
}
