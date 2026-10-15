import XCTest

final class BookmarkNavigationUITests: XCTestCase {
    @MainActor
    func testBookmarkOpensMarkdownReaderAndReturnsToBookmarks() throws {
        let app = launchApp(supportsMarkdown: true)
        openBookmark(in: app)
        XCTAssertTrue(app.staticTexts["topic-preview-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.scrollViews["topic-markdown-preview"].exists)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["Remove bookmark"].exists)
        app.buttons["Dismiss topic"].tap()
        XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
        // Reopening creates a fresh loader; removing the bookmark updates the list behind it.
        app.buttons["bookmark-https://example.com/t/saved/123"].tap()
        XCTAssertTrue(app.buttons["Remove bookmark"].waitForExistence(timeout: 10))
        app.buttons["Remove bookmark"].tap()
        app.buttons["Dismiss topic"].tap()
        XCTAssertTrue(app.staticTexts["No Bookmarks"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBookmarkWithoutMarkdownOpensInternalWebView() throws {
        let app = launchApp(supportsMarkdown: false)
        openBookmark(in: app)
        XCTAssertTrue(app.webViews.staticTexts["Saved website content"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        app.buttons["Dismiss topic"].tap()
        XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved topic"].exists)
    }

    @MainActor
    private func launchApp(supportsMarkdown: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "FORUM_INDEX_UI_TESTING": "1",
            "FORUM_INDEX_UI_TEST_RESET_SUBJECTS": "1",
            "FORUM_INDEX_UI_TEST_RESET_BOOKMARKS": "1",
            "FORUM_INDEX_UI_TEST_TOPIC": """
            {"id":123,"title":"Saved topic","url":"https://example.com/t/saved/123","forum":{"id":1,"name":"Example Forum","slug":"example","base_url":"https://example.com","supports_markdown":\(supportsMarkdown)}}
            """,
            "FORUM_INDEX_UI_TEST_MARKDOWN": "# Saved topic\n\nSaved discussion content.",
            "FORUM_INDEX_UI_TEST_HTML": "<html><body><p>Saved website content</p></body></html>"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func openBookmark(in app: XCUIApplication) {
        let topic = app.buttons["topic-1-123"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.press(forDuration: 1)
        let save = app.buttons["topic-context-star"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        app.buttons["Show bookmarks"].tap()
        XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
        let saved = app.buttons["bookmark-https://example.com/t/saved/123"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
    }
}
