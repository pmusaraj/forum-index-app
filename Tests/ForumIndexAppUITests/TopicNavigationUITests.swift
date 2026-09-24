import XCTest

final class TopicNavigationUITests: XCTestCase {
    @MainActor
    func testContentPagingAndNativeBackRevealCurrentRow() {
        let app = launchReader()
        let first = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        first.tap()
        XCTAssertTrue(app.buttons["Dismiss topic"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars.count, 0)
        XCTAssertEqual(app.sheets.count, 0)
        assertTopic(1, app: app)
        swipeContent(app, left: true)
        assertTopic(2, app: app)
        swipeContent(app, left: true)
        assertTopic(3, app: app)
        swipeContent(app, left: false)
        assertTopic(2, app: app)
        app.buttons["Dismiss topic"].firstMatch.tap()
        let row = app.buttons["topic-1-2"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.isSelected)
    }

    @MainActor
    func testLeadingEdgeReturnsToListEvenAfterPaging() {
        let app = launchReader()
        XCTAssertTrue(app.buttons["topic-1-1"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["topic-1-1"].firstMatch.tap()
        assertTopic(1, app: app)
        swipeContent(app, left: true)
        assertTopic(2, app: app)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        let row = app.buttons["topic-1-2"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.isSelected)
        XCTAssertFalse(app.staticTexts["topic-preview-title"].exists)
    }

    @MainActor
    func testBackWithoutPagingPreservesListOffset() {
        let app = launchReader()
        XCTAssertTrue(app.buttons["topic-1-1"].firstMatch.waitForExistence(timeout: 15))
        app.swipeUp()
        let row = app.buttons["topic-1-12"].firstMatch
        if !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        let originalY = row.frame.minY
        row.tap()
        assertTopic(12, app: app)
        app.buttons["Dismiss topic"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.frame.minY, originalY, accuracy: 2)
    }

    @MainActor
    func testPagingToAnOffscreenRowRestoresItOnBack() {
        let app = launchReader()
        XCTAssertTrue(app.buttons["topic-1-1"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["topic-1-1"].firstMatch.tap()
        assertTopic(1, app: app)
        for index in 2...10 {
            swipeContent(app, left: true)
            assertTopic(index, app: app)
        }
        app.buttons["Dismiss topic"].firstMatch.tap()
        let row = app.buttons["topic-1-10"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.isSelected)
    }

    @MainActor
    func testWebTopicsAlsoPageAndKeepNativeEdgeBack() {
        let app = launchReader(markdown: false)
        XCTAssertTrue(app.buttons["topic-1-1"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["topic-1-1"].firstMatch.tap()
        XCTAssertEqual(app.navigationBars.count, 0)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))
        swipeContent(app, left: true)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        let row = app.buttons["topic-1-2"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isSelected)
    }

    @MainActor
    func testCancelledInteractiveBackKeepsCurrentTopic() {
        let app = launchReader()
        XCTAssertTrue(app.buttons["topic-1-1"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["topic-1-1"].firstMatch.tap()
        assertTopic(1, app: app)
        swipeContent(app, left: true)
        assertTopic(2, app: app)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        assertTopic(2, app: app)
        XCTAssertEqual(app.navigationBars.count, 0)
        swipeContent(app, left: true)
        assertTopic(3, app: app)
    }

    @MainActor
    private func launchReader(markdown: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = markdown ? "1" : "0"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = "A topic preview with enough content to swipe between topics.\n\nSwipe through the conversation, or use the native Back button to return to the list."
        app.launch()
        return app
    }

    @MainActor
    private func assertTopic(_ index: Int, app: XCUIApplication) {
        let title = app.staticTexts["topic-preview-title"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Main fixture topic \(index)"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 8), .completed)
    }

    @MainActor
    private func swipeContent(_ app: XCUIApplication, left: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.8 : 0.2, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.2 : 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
