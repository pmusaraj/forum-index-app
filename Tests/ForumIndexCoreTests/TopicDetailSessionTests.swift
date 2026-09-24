import XCTest
@testable import ForumIndexCore

@MainActor
final class TopicDetailSessionTests: XCTestCase {
    func testOrderedSelectionFiltersInvalidTopicsAndPreservesCompositeIdentity() throws {
        let topics = [topic(1, forumID: 1), topic(2, forumID: 1, valid: false), topic(1, forumID: 2), topic(3, forumID: 1)]
        let session = try XCTUnwrap(TopicDetailSession(topics: topics, selectedID: topics[2].presentationID))
        XCTAssertEqual(session.orderedIDs, [topics[0].presentationID, topics[2].presentationID, topics[3].presentationID])
        XCTAssertEqual(session.currentIndex, 1)
        session.select(index: 2)
        XCTAssertEqual(session.currentID, topics[3].presentationID)
        XCTAssertTrue(session.didChangeItem)
        session.select(index: 10)
        XCTAssertEqual(session.currentIndex, 2)
        session.select(index: 1)
        XCTAssertFalse(session.didChangeItem)
        XCTAssertTrue(session.hasPaged)
    }

    func testEmptyOrUnavailableSelectionCannotOpenDetail() {
        XCTAssertNil(TopicDetailSession(topics: [], selectedID: TopicPresentationID(forumID: 1, topicID: 1)))
        let invalid = topic(1, forumID: 1, valid: false)
        XCTAssertNil(TopicDetailSession(topics: [invalid], selectedID: invalid.presentationID))
    }

    private func topic(_ id: Int, forumID: Int, valid: Bool = true) -> Topic {
        Topic(id: id, title: "Topic", url: valid ? URL(string: "https://example.com/t/\(id)") : nil,
              excerpt: nil, forum: ForumSummary(id: forumID, name: "Forum", slug: "forum", baseURL: nil))
    }
}
