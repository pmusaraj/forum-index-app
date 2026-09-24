import XCTest

final class MarkdownPreviewUITests: XCTestCase {
    @MainActor
    func testLegacyForumDomainRedirectLoadsTopic() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_TOPIC"] = #"{"id":5823105,"title":"The listening e","url":"https://community.security.eufy.com/t/the-listening-e/5823105","engagement":{"replies":1},"forum":{"id":1,"name":"Eufy","slug":"eufy","base_url":"https://community.security.eufy.com","supports_markdown":false}}"#
        app.launch()
        let topic = app.buttons["topic-1-5823105"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["Couldn’t load this topic"].exists)
    }

    @MainActor
    func testMetaDiscoursePostLayoutAndStickyHeader() throws {
        let app = try launchExample()
        let title = app.staticTexts["topic-preview-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Require LLM-generated themes & plugins to be tagged as such")
        XCTAssertTrue(app.staticTexts["darkpixlz"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["32 replies"].exists)
        XCTAssertFalse(app.buttons["Open in browser"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "<div class=")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "URL:")).firstMatch.exists)
        let forumName = app.staticTexts["Discourse Meta"].firstMatch
        XCTAssertTrue(forumName.exists)
        let headerY = forumName.frame.minY
        capture(app, name: "Meta-topic-top")

        app.scrollViews["topic-markdown-preview"].swipeUp(velocity: .slow)
        XCTAssertEqual(forumName.frame.minY, headerY, accuracy: 1)
        XCTAssertTrue(forumName.isHittable)
        capture(app, name: "Meta-topic-posts-sticky-header")
    }

    @MainActor
    func testRepliesAutomaticallyLoadNearTheEnd() throws {
        let app = try launchExample(paginated: true)
        XCTAssertTrue(app.staticTexts["topic-preview-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["topic-full-html"].exists)
        let author = app.staticTexts["page-two-author"]
        XCTAssertFalse(author.exists)
        for _ in 0..<12 {
            if author.exists { break }
            app.scrollViews["topic-markdown-preview"].swipeUp()
        }
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "topic-preview-title").count, 1)
        XCTAssertTrue(app.buttons["topic-header-full-html"].exists)
        XCTAssertFalse(app.buttons["topic-full-html"].exists)
    }

    @MainActor
    func testHeaderOpensBackgroundLoadedPage() throws {
        let app = try launchExample()
        let button = app.buttons["topic-header-full-html"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ready"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 25), .completed)
        XCTAssertTrue(app.scrollViews["topic-markdown-preview"].exists)
        app.scrollViews["topic-markdown-preview"].swipeUp(velocity: .slow)
        let author = app.staticTexts["RGJ"].firstMatch
        XCTAssertTrue(author.isHittable)
        let authorY = author.frame.minY
        let headerY = button.frame.minY
        button.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["topic-markdown-preview"].isHittable)
        XCTAssertTrue(button.isHittable)
        XCTAssertEqual(button.label, "Show Markdown preview")
        XCTAssertEqual(button.frame.minY, headerY, accuracy: 1)
        button.tap()
        XCTAssertTrue(app.scrollViews["topic-markdown-preview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertEqual(author.frame.minY, authorY, accuracy: 2)
        XCTAssertEqual(button.label, "View full topic")
        button.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchExample(paginated: Bool = false) throws -> XCUIApplication {
        let bundle = Bundle(for: Self.self)
        let topicURL = try XCTUnwrap(bundle.url(forResource: "MetaDiscourseTopic", withExtension: "json", subdirectory: "Fixtures"))
        let markdownURL = try XCTUnwrap(bundle.url(forResource: "MetaDiscourseTopic", withExtension: "md", subdirectory: "Fixtures"))
        var markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        var nextPages: [String: String] = [:]
        if paginated, let separator = markdown.range(of: "\n---\n") {
            markdown = String(markdown[..<separator.lowerBound])
            markdown += String(repeating: "\n\nMore first-page discussion to read before the next page. This paragraph keeps the initial page taller than two viewports so scrolling is required to load further replies.", count: 10)
            let nextURL = "https://meta.discourse.org/t/require-llm-generated-themes-plugins-to-be-tagged-as-such/412871.md?page=2"
            markdown += "\n\n[Next page](\(nextURL))"
            nextPages[nextURL] = """
            # Example topic

            **URL:** https://meta.discourse.org/t/require-llm-generated-themes-plugins-to-be-tagged-as-such/412871
            **Page:** 2

            <div class="post-metadata">
            ### Author: [@page-two-author](https://meta.discourse.org/u/page-two-author)
            </div>

            A reply automatically loaded from page two.
            """
        }
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_TOPIC"] = try String(contentsOf: topicURL, encoding: .utf8)
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = markdown
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN_PAGES"] = String(decoding: try JSONEncoder().encode(nextPages), as: UTF8.self)
        app.launch()
        let topic = app.buttons["topic-1-412871"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
