import XCTest
@testable import ForumIndexCore

final class TopicPresentationTests: XCTestCase {
    func testWebNavigationPolicyAllowsOnlyAbsoluteHTTPSDestinations() {
        let httpsURL = URL(string: "https://forums.example.com/t/1")!

        XCTAssertEqual(WebNavigationPolicy.acceptedURL(httpsURL), httpsURL)
        XCTAssertTrue(WebNavigationPolicy.allows(httpsURL))
        XCTAssertFalse(WebNavigationPolicy.allows(URL(string: "http://forums.example.com/t/1")))
        XCTAssertFalse(WebNavigationPolicy.allows(URL(string: "ftp://forums.example.com/file")))
        XCTAssertFalse(WebNavigationPolicy.allows(URL(string: "/relative/path")))
        XCTAssertFalse(WebNavigationPolicy.allows(URL(string: "https:///missing-host")))
        XCTAssertFalse(WebNavigationPolicy.allows(nil))
    }

    func testFirstTapExpandsAndPreloadsThenSecondTapPresentsSameURL() {
        var state = TopicActivationState(destinationID: "parent:swift")
        let topicID = presentationID(42)
        let url = URL(string: "https://forums.example.com/t/42")!

        XCTAssertEqual(state.activate(topicID: topicID, url: url), .preload(url))
        XCTAssertEqual(state.expandedTopicID, topicID)
        XCTAssertNil(state.presentedURL)

        XCTAssertEqual(state.activate(topicID: topicID, url: url), .present(url))
        XCTAssertEqual(state.presentedURL, url)
    }

    func testFirstTapOnDifferentTopicReplacesExpansionAndPreload() {
        var state = TopicActivationState(destinationID: "parent:swift")
        let firstURL = URL(string: "https://one.example/t/1")!
        let secondURL = URL(string: "https://two.example/t/2")!

        _ = state.activate(topicID: presentationID(1), url: firstURL)
        XCTAssertEqual(state.activate(topicID: presentationID(2), url: secondURL), .preload(secondURL))
        XCTAssertEqual(state.expandedTopicID, presentationID(2))
        XCTAssertNil(state.presentedURL)
    }

    func testEqualLocalTopicIDsFromDifferentForumsRemainDistinct() {
        var state = TopicActivationState(destinationID: "parent:swift")
        let firstURL = URL(string: "https://one.example/t/7")!
        let secondURL = URL(string: "https://two.example/t/7")!

        XCTAssertEqual(state.activate(topicID: presentationID(7, forumID: 1), url: firstURL), .preload(firstURL))
        XCTAssertEqual(state.activate(topicID: presentationID(7, forumID: 2), url: secondURL), .preload(secondURL))
        XCTAssertEqual(state.expandedTopicID, presentationID(7, forumID: 2))
        XCTAssertNil(state.presentedURL)
    }

    func testURLLessInsecureOrInvalidTopicExpandsButNeverPresents() {
        var state = TopicActivationState(destinationID: "parent:swift")

        XCTAssertEqual(state.activate(topicID: presentationID(9), url: nil), .none)
        XCTAssertEqual(state.expandedTopicID, presentationID(9))
        XCTAssertEqual(state.activate(topicID: presentationID(9), url: nil), .none)
        XCTAssertNil(state.presentedURL)

        let fileURL = URL(fileURLWithPath: "/tmp/topic")
        XCTAssertEqual(state.activate(topicID: presentationID(10), url: fileURL), .none)
        XCTAssertEqual(state.activate(topicID: presentationID(10), url: fileURL), .none)
        XCTAssertNil(state.presentedURL)

        let insecureURL = URL(string: "http://forums.example/t/11")!
        XCTAssertEqual(state.activate(topicID: presentationID(11), url: insecureURL), .none)
        XCTAssertEqual(state.activate(topicID: presentationID(11), url: insecureURL), .none)
        XCTAssertNil(state.presentedURL)
    }

    func testSecondTapPresentsURLArmedByFirstTapEvenIfInputChanges() {
        var state = TopicActivationState(destinationID: "parent:swift")
        let topicID = presentationID(1)
        let armed = URL(string: "https://forums.example/t/1")!
        let changed = URL(string: "https://other.example/t/1")!

        XCTAssertEqual(state.activate(topicID: topicID, url: armed), .preload(armed))
        XCTAssertEqual(state.activate(topicID: topicID, url: changed), .present(armed))
    }

    func testDestinationChangeResetsExpansionAndPresentation() {
        var state = TopicActivationState(destinationID: "parent:swift")
        let topicID = presentationID(1)
        let url = URL(string: "https://forums.example/t/1")!
        _ = state.activate(topicID: topicID, url: url)
        _ = state.activate(topicID: topicID, url: url)

        state.destinationDidChange(to: "child:swift/ios")

        XCTAssertNil(state.expandedTopicID)
        XCTAssertNil(state.presentedURL)
        XCTAssertEqual(state.destinationID, "child:swift/ios")
    }

    func testSameDestinationDoesNotResetExpansion() {
        var state = TopicActivationState(destinationID: "parent:swift")
        _ = state.activate(topicID: presentationID(1), url: nil)

        state.destinationDidChange(to: "parent:swift")

        XCTAssertEqual(state.expandedTopicID, presentationID(1))
    }

    func testFaviconUsesRootHTTPSOriginAndPreservesPort() {
        let base = URL(string: "https://forums.example.com:8443/community/latest?order=new")!
        XCTAssertEqual(
            ForumPresentation.faviconURL(for: base)?.absoluteString,
            "https://forums.example.com:8443/favicon.ico"
        )
        XCTAssertNil(ForumPresentation.faviconURL(for: URL(string: "http://forums.example.com")!))
        XCTAssertNil(ForumPresentation.faviconURL(for: URL(string: "file:///tmp/forum")!))
    }

    func testMonogramUsesFirstAlphanumericGraphemeIncludingUnicode() {
        XCTAssertEqual(ForumPresentation.monogram(for: "  — Éclair"), "É")
        XCTAssertEqual(ForumPresentation.monogram(for: "👨‍👩‍👧‍👦 東京"), "東")
        XCTAssertEqual(ForumPresentation.monogram(for: "---"), "?")
        XCTAssertEqual(ForumPresentation.monogram(for: ""), "?")
    }

    func testExcerptNormalizationRemovesMarkupDecodesEntitiesAndCollapsesWhitespace() {
        XCTAssertEqual(
            ForumPresentation.normalizedExcerpt(" <p>Hello&nbsp; <strong>world</strong> &amp; &#x1F30D;</p>\nNext "),
            "Hello world & 🌍 Next"
        )
        XCTAssertNil(ForumPresentation.normalizedExcerpt(" <br> \n "))
    }

    private func presentationID(_ topicID: Int, forumID: Int = 1) -> TopicPresentationID {
        TopicPresentationID(forumID: forumID, topicID: topicID)
    }
}
