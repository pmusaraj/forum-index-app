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
        XCTAssertFalse(WebNavigationPolicy.allows(URL(string: "https://user:password@forums.example.com/t/1")))
        XCTAssertFalse(WebNavigationPolicy.allows(nil))
    }

    func testExternalWebNavigationRequiresADifferentHTTPSHost() {
        let page = URL(string: "https://forums.example.com/t/1")!
        let external = URL(string: "https://example.org/article")!

        XCTAssertEqual(WebNavigationPolicy.externalURL(external, relativeTo: page), external)
        XCTAssertNil(WebNavigationPolicy.externalURL(URL(string: "https://forums.example.com/t/2"), relativeTo: page))
        XCTAssertEqual(
            WebNavigationPolicy.externalURL(URL(string: "https://forums.example.com:8443/t/2"), relativeTo: page),
            URL(string: "https://forums.example.com:8443/t/2")
        )
        XCTAssertNil(WebNavigationPolicy.externalURL(URL(string: "http://example.org/article"), relativeTo: page))
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

    func testWebPageBecomesVisibleAtCommitBeforeLoadingFinishes() {
        var state = WebPageLoadState()

        let generation = state.beginLoading()
        XCTAssertFalse(state.isReady)
        XCTAssertTrue(state.isLoading)

        state.commit(generation)
        XCTAssertTrue(state.isReady)
        XCTAssertTrue(state.isLoading)

        state.finish(generation)
        XCTAssertTrue(state.isReady)
        XCTAssertFalse(state.isLoading)
    }

    func testOnlyLatestWebPageLoadCanBecomeVisible() {
        var state = WebPageLoadState()

        let first = state.beginLoading()
        let second = state.beginLoading()
        state.commit(first)
        state.fail(first, message: "Old request failed")

        XCTAssertFalse(state.isReady)
        XCTAssertNil(state.errorMessage)

        state.commit(second)
        XCTAssertTrue(state.isReady)
    }

    func testClearingAReadyPageHidesItAndFencesItsNavigation() {
        var state = WebPageLoadState()
        let generation = state.beginLoading()
        state.commit(generation)

        state.clear()
        state.commit(generation)

        XCTAssertFalse(state.isReady)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.errorMessage)
    }

    func testBlankNavigationAllowanceIsOneShotAndCancellable() {
        var allowance = WebPageClearNavigationAllowance()
        let blank = URL(string: "about:blank")!

        allowance.begin()
        XCTAssertFalse(allowance.consumeIfAllowed(URL(string: "https://example.com")))
        XCTAssertTrue(allowance.consumeIfAllowed(blank))
        XCTAssertFalse(allowance.consumeIfAllowed(blank))

        allowance.begin()
        allowance.cancel()
        XCTAssertFalse(allowance.consumeIfAllowed(blank))
    }

    func testForumAssetWarmupUsesOneOriginFaviconPerForum() {
        var state = ForumAssetWarmupState()
        let firstTopic = URL(string: "https://forum.example:8443/t/one?tracking=1#post-2")!
        let secondTopic = URL(string: "https://forum.example:8443/t/two")!

        XCTAssertEqual(
            state.assetURL(forForumID: 1, topicURL: firstTopic),
            URL(string: "https://forum.example:8443/favicon.ico")
        )
        XCTAssertNil(state.assetURL(forForumID: 1, topicURL: secondTopic))
        XCTAssertNil(state.assetURL(forForumID: 2, topicURL: URL(string: "http://unsafe.example/t/1")))
        XCTAssertEqual(
            state.assetURL(forForumID: 2, topicURL: URL(string: "https://other.example/t/1")),
            URL(string: "https://other.example/favicon.ico")
        )
    }

    func testExcerptNormalizationRemovesMarkupDecodesEntitiesAndCollapsesWhitespace() {
        XCTAssertEqual(
            ForumPresentation.normalizedExcerpt(" <p>Hello&nbsp; <strong>world</strong> &amp; &#x1F30D;</p>\nNext "),
            "Hello world & 🌍 Next"
        )
        XCTAssertNil(ForumPresentation.normalizedExcerpt(" <br> \n "))
    }

    func testForumDisplayNameIsCappedAtSixtyCharactersWithEllipsis() {
        let longName = String(repeating: "a", count: 61)

        XCTAssertEqual(ForumPresentation.displayName("Short forum"), "Short forum")
        XCTAssertEqual(ForumPresentation.displayName(longName), String(longName.prefix(59)) + "…")
        XCTAssertEqual(ForumPresentation.displayName(longName).count, 60)
    }

    func testForumDisplayNameSeparatesOpenSource() {
        XCTAssertEqual(ForumPresentation.displayName("OpenSource"), "Open Source")
    }
}
