import XCTest

final class SwipeNavigationUITests: XCTestCase {
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

        let firstTopic = app.buttons["topic-1-1"].firstMatch
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
}