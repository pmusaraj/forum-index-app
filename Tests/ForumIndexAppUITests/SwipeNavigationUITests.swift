import XCTest

final class SwipeNavigationUITests: XCTestCase {
    @MainActor
    func testPagerSettlesOnAFullWidthPageAfterRepeatedSwipes() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["Main"].waitForExistence(timeout: 15))
        for _ in 0..<4 {
            app.swipeLeft(velocity: .slow)
            app.swipeRight(velocity: .slow)
        }
        app.swipeLeft(velocity: .slow)

        let topic = app.buttons["topic-2-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(topic.frame.minX, -1)
        XCTAssertLessThanOrEqual(topic.frame.maxX, app.frame.maxX + 1)
    }

    @MainActor
    func testTabTapSelectsItsPage() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launch()

        let ai = app.buttons["AI"]
        XCTAssertTrue(ai.waitForExistence(timeout: 15))
        ai.tap()

        let selected = NSPredicate(format: "value == %@", "Selected")
        expectation(for: selected, evaluatedWith: ai)
        waitForExpectations(timeout: 8)
        let topic = app.buttons["topic-2-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(topic.frame.minX, -1)
        XCTAssertLessThanOrEqual(topic.frame.maxX, app.frame.maxX + 1)
    }

    @MainActor
    func testTopicSheetUsesCompactDismissControl() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["Main"].waitForExistence(timeout: 15))
        app.swipeLeft(velocity: .slow)

        let topic = app.buttons["topic-2-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        topic.tap()

        let close = app.buttons["Close topic"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Done"].exists)
        close.tap()
        XCTAssertTrue(topic.waitForExistence(timeout: 3))
    }

    @MainActor
    func testTabsStayFixedAndSelectedTabScrollsIntoView() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launch()

        let main = app.buttons["Main"]
        XCTAssertTrue(main.waitForExistence(timeout: 15))
        let tabY = main.frame.midY
        let mainX = main.frame.minX

        app.swipeLeft(velocity: .slow)
        let ai = app.buttons["AI"]
        XCTAssertTrue(ai.waitForExistence(timeout: 3))
        XCTAssertEqual(ai.value as? String, "Selected")
        XCTAssertEqual(main.frame.minX, mainX, accuracy: 2)

        app.swipeLeft(velocity: .slow)
        let rightmost = app.buttons["Far Right Category With Long Name"]
        XCTAssertTrue(rightmost.waitForExistence(timeout: 3))
        XCTAssertEqual(rightmost.value as? String, "Selected")
        XCTAssertTrue(rightmost.isHittable)
        XCTAssertEqual(rightmost.frame.midY, tabY, accuracy: 2)
    }

    @MainActor
    func testHorizontalSwipesNavigateBothDirectionsWithoutStealingVerticalDrag() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launch()

        let main = app.buttons["Main"]
        let ai = app.buttons["AI"]

        XCTAssertTrue(main.waitForExistence(timeout: 15))
        XCTAssertTrue(ai.waitForExistence(timeout: 5))
        XCTAssertEqual(main.value as? String, "Selected")

        app.swipeLeft(velocity: .slow)

        let selected = NSPredicate(format: "value == %@", "Selected")
        expectation(for: selected, evaluatedWith: ai)
        waitForExpectations(timeout: 8)

        let firstTopic = app.buttons["topic-2-1"].firstMatch
        XCTAssertTrue(firstTopic.waitForExistence(timeout: 3))
        let initialY = firstTopic.frame.minY
        let verticalStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let verticalEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        verticalStart.press(forDuration: 0.05, thenDragTo: verticalEnd)
        XCTAssertEqual(ai.value as? String, "Selected")
        let scrolled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !firstTopic.exists || firstTopic.frame.minY < initialY - 20
            },
            object: firstTopic
        )
        XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 3), .completed)

        app.swipeRight(velocity: .slow)
        expectation(for: selected, evaluatedWith: main)
        waitForExpectations(timeout: 8)
    }

    @MainActor
    func testEachPageRetainsItsVerticalScrollPosition() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launch()

        let main = app.buttons["Main"]
        let ai = app.buttons["AI"]
        let firstMainTopic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(firstMainTopic.waitForExistence(timeout: 15))
        let initialY = firstMainTopic.frame.minY

        app.swipeUp(velocity: .slow)
        let mainScrolled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                !firstMainTopic.exists || firstMainTopic.frame.minY < initialY - 20
            },
            object: firstMainTopic
        )
        XCTAssertEqual(XCTWaiter.wait(for: [mainScrolled], timeout: 3), .completed)

        app.swipeLeft(velocity: .slow)
        let selected = NSPredicate(format: "value == %@", "Selected")
        expectation(for: selected, evaluatedWith: ai)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["topic-2-1"].firstMatch.waitForExistence(timeout: 3))

        app.swipeLeft(velocity: .slow)
        let farRight = app.buttons["Far Right Category With Long Name"]
        expectation(for: selected, evaluatedWith: farRight)
        waitForExpectations(timeout: 8)

        app.swipeRight(velocity: .slow)
        expectation(for: selected, evaluatedWith: ai)
        waitForExpectations(timeout: 8)
        app.swipeRight(velocity: .slow)
        expectation(for: selected, evaluatedWith: main)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(!firstMainTopic.exists || firstMainTopic.frame.minY < initialY - 20)
    }
}
