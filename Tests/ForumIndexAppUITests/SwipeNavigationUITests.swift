import XCTest

final class SwipeNavigationUITests: XCTestCase {
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

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: end)

        let selected = NSPredicate(format: "value == %@", "Selected")
        expectation(for: selected, evaluatedWith: ai)
        waitForExpectations(timeout: 8)

        let firstTopic = app.buttons["topic-1-1"]
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

        end.press(forDuration: 0.05, thenDragTo: start)
        expectation(for: selected, evaluatedWith: main)
        waitForExpectations(timeout: 8)
    }
}