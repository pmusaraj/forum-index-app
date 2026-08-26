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

    func testFirstTapPresentsTopicURLImmediately() {
        var state = TopicActivationState(destinationID: "parent:swift")
        let url = URL(string: "https://forums.example.com/t/42")!

        XCTAssertEqual(state.activate(url: url), .present(url))
        XCTAssertEqual(state.presentedURL, url)
    }

    func testTappingAnotherTopicPresentsItsURLImmediately() {
        var state = TopicActivationState(destinationID: "parent:swift")
        let firstURL = URL(string: "https://one.example/t/1")!
        let secondURL = URL(string: "https://two.example/t/2")!

        XCTAssertEqual(state.activate(url: firstURL), .present(firstURL))
        XCTAssertEqual(state.activate(url: secondURL), .present(secondURL))
        XCTAssertEqual(state.presentedURL, secondURL)
    }

    func testURLLessInsecureOrInvalidTopicNeverPresents() {
        var state = TopicActivationState(destinationID: "parent:swift")

        XCTAssertEqual(state.activate(url: nil), .none)
        XCTAssertNil(state.presentedURL)

        let fileURL = URL(fileURLWithPath: "/tmp/topic")
        XCTAssertEqual(state.activate(url: fileURL), .none)
        XCTAssertNil(state.presentedURL)

        let insecureURL = URL(string: "http://forums.example/t/11")!
        XCTAssertEqual(state.activate(url: insecureURL), .none)
        XCTAssertNil(state.presentedURL)
    }

    func testDestinationChangeDismissesPresentation() {
        var state = TopicActivationState(destinationID: "parent:swift")
        let url = URL(string: "https://forums.example.com/t/1")!
        _ = state.activate(url: url)

        state.destinationDidChange(to: "child:swift/ios")

        XCTAssertNil(state.presentedURL)
        XCTAssertEqual(state.destinationID, "child:swift/ios")
    }

    func testSameDestinationDoesNotDismissPresentation() {
        var state = TopicActivationState(destinationID: "parent:swift")
        let url = URL(string: "https://forums.example.com/t/1")!
        _ = state.activate(url: url)

        state.destinationDidChange(to: "parent:swift")

        XCTAssertEqual(state.presentedURL, url)
    }


    func testExcerptNormalizationRemovesMarkupDecodesEntitiesAndCollapsesWhitespace() {
        XCTAssertEqual(
            ForumPresentation.normalizedExcerpt(" <p>Hello&nbsp; <strong>world</strong> &amp; &#x1F30D;</p>\nNext "),
            "Hello world & 🌍 Next"
        )
        XCTAssertNil(ForumPresentation.normalizedExcerpt(" <br> \n "))
    }
}
