import XCTest

final class SwipeNavigationUITests: XCTestCase {
    @MainActor
    func testScrollingTopicsKeepsHeaderVisible() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()

        let title = app.staticTexts["reader-title"]
        let main = app.buttons["Main"]
        let anchor = app.buttons["topic-1-8"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(main.exists)
        XCTAssertTrue(anchor.waitForExistence(timeout: 3))
        let initialTitleY = title.frame.minY
        let initialTabY = main.frame.minY
        let initialAnchorY = anchor.frame.minY

        app.swipeUp(velocity: .slow)

        let contentScrolled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                anchor.exists && anchor.frame.minY < initialAnchorY - 20
            },
            object: anchor
        )
        XCTAssertEqual(XCTWaiter.wait(for: [contentScrolled], timeout: 3), .completed)
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.frame.minY, initialTitleY, accuracy: 2)
        XCTAssertEqual(main.frame.minY, initialTabY, accuracy: 2)
    }

    @MainActor
    func testLoadingSkeletonAndSubjectPickerSelection() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_SLOW_FEED"] = "1"
        app.launch()

        let skeleton = app.descendants(matching: .any)["topic-list-skeleton-main-feed"]
        XCTAssertTrue(skeleton.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Far Right Category With Long Name"].exists)
        let customize = app.buttons["Customize subjects"]
        XCTAssertTrue(customize.waitForExistence(timeout: 3))
        customize.tap()
        XCTAssertTrue(app.descendants(matching: .any)["subject-picker"].waitForExistence(timeout: 3))
        let farRightToggle = app.buttons["subject-toggle-parent:far-right"]
        XCTAssertTrue(farRightToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(farRightToggle.value as? String, "Unchecked")
        XCTAssertEqual(app.buttons["subject-toggle-parent:technology"].value as? String, "Checked")
        XCTAssertEqual(app.buttons["subject-toggle-parent:sport"].value as? String, "Checked")
        let mainToggle = app.buttons["subject-toggle-main-feed"]
        XCTAssertEqual(mainToggle.value as? String, "Checked")
        mainToggle.tap()
        app.buttons["Done"].tap()

        XCTAssertFalse(app.buttons["Main"].exists)
        let ai = app.buttons["AI"]
        XCTAssertTrue(ai.waitForExistence(timeout: 3))
        XCTAssertEqual(ai.value as? String, "Selected")
        XCTAssertTrue(app.buttons["topic-2-1"].firstMatch.waitForExistence(timeout: 5))

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FORUM_INDEX_UI_TEST_RESET_SUBJECTS")
        app.launchEnvironment.removeValue(forKey: "FORUM_INDEX_UI_TEST_SLOW_FEED")
        app.launch()
        XCTAssertTrue(app.buttons["AI"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Main"].exists)
        XCTAssertEqual(app.buttons["AI"].value as? String, "Selected")
    }

    @MainActor
    func testMainCanBeDraggedAfterAI() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Customize subjects"].waitForExistence(timeout: 15))
        app.buttons["Customize subjects"].tap()
        let main = app.buttons["subject-toggle-main-feed"]
        let tech = app.buttons["subject-toggle-parent:technology"]
        XCTAssertTrue(main.waitForExistence(timeout: 3))
        main.press(forDuration: 1, thenDragTo: tech)
        app.buttons["Done"].tap()
        XCTAssertLessThan(app.buttons["AI"].frame.minX, app.buttons["Main"].frame.minX)
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FORUM_INDEX_UI_TEST_RESET_SUBJECTS")
        app.launch()
        XCTAssertTrue(app.buttons["AI"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["AI"].value as? String, "Selected")
    }

    @MainActor
    func testOpenedTopicStylePersists() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_OPENED_TOPICS"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Main"].waitForExistence(timeout: 15))
        app.swipeLeft(velocity: .slow)
        let topic = app.buttons["topic-2-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        XCTAssertEqual(topic.value as? String, "Not opened")
        topic.tap()
        XCTAssertTrue(app.buttons["Dismiss topic"].waitForExistence(timeout: 5))
        app.buttons["Dismiss topic"].tap()
        XCTAssertEqual(topic.value as? String, "Opened")
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FORUM_INDEX_UI_TEST_RESET_OPENED_TOPICS")
        app.launch()
        XCTAssertTrue(app.buttons["Main"].waitForExistence(timeout: 15))
        app.swipeLeft(velocity: .slow)
        XCTAssertEqual(app.buttons["topic-2-1"].firstMatch.value as? String, "Opened")
    }

    @MainActor
    func testPagerSettlesOnAFullWidthPageAfterRepeatedSwipes() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["Main"].waitForExistence(timeout: 15))
        for _ in 0..<4 {
            app.swipeLeft(velocity: .slow)
            app.swipeRight(velocity: .slow)
        }
        app.swipeLeft(velocity: .slow)

        let pager = app.scrollViews["feed-pager"]
        let page = app.descendants(matching: .any)
            .matching(identifier: "feed-page-parent:ai")
            .firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertEqual(page.frame.minX, pager.frame.minX, accuracy: 1)
        XCTAssertEqual(page.frame.maxX, pager.frame.maxX, accuracy: 1)
    }

    @MainActor
    func testTabTapSelectsItsPage() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()

        let ai = app.buttons["AI"]
        XCTAssertTrue(ai.waitForExistence(timeout: 15))
        ai.tap()
        app.buttons["Main"].tap()
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
    func testTopicSheetActionsAndPersistentBookmark() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_BOOKMARKS"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["Main"].waitForExistence(timeout: 15))
        app.swipeLeft(velocity: .slow)

        let topic = app.buttons["topic-2-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        topic.tap()

        XCTAssertTrue(app.buttons["Share topic"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open in Safari"].exists)
        let bookmark = app.buttons["Bookmark topic"]
        XCTAssertTrue(bookmark.exists)
        bookmark.tap()
        XCTAssertTrue(app.buttons["Remove bookmark"].waitForExistence(timeout: 3))
        app.buttons["Dismiss topic"].tap()

        let showBookmarks = app.buttons["Show bookmarks"]
        XCTAssertTrue(showBookmarks.waitForExistence(timeout: 3))
        showBookmarks.tap()
        XCTAssertTrue(app.staticTexts["AI fixture topic 1"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FORUM_INDEX_UI_TEST_RESET_BOOKMARKS")
        app.launch()
        XCTAssertTrue(app.buttons["Show bookmarks"].waitForExistence(timeout: 15))
        app.buttons["Show bookmarks"].tap()
        XCTAssertTrue(app.staticTexts["AI fixture topic 1"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testTabsStayFixedAndSelectedTabScrollsIntoView() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
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
        let tech = app.buttons["Tech"]
        let selected = NSPredicate(format: "value == %@", "Selected")
        expectation(for: selected, evaluatedWith: tech)
        waitForExpectations(timeout: 8)
        XCTAssertEqual(tech.frame.midY, tabY, accuracy: 2)
    }

    @MainActor
    func testHorizontalSwipesNavigateBothDirectionsWithoutStealingVerticalDrag() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
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
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()

        let main = app.buttons["Main"]
        let ai = app.buttons["AI"]
        let mainAnchor = app.buttons["topic-1-8"].firstMatch
        XCTAssertTrue(mainAnchor.waitForExistence(timeout: 15))
        let initialY = mainAnchor.frame.minY

        app.swipeUp(velocity: .slow)
        let mainScrolled = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                mainAnchor.exists && mainAnchor.frame.minY < initialY - 20
            },
            object: mainAnchor
        )
        XCTAssertEqual(XCTWaiter.wait(for: [mainScrolled], timeout: 3), .completed)
        let scrolledY = mainAnchor.frame.minY

        app.swipeLeft(velocity: .slow)
        let selected = NSPredicate(format: "value == %@", "Selected")
        expectation(for: selected, evaluatedWith: ai)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["topic-2-1"].firstMatch.waitForExistence(timeout: 3))

        app.swipeLeft(velocity: .slow)
        let tech = app.buttons["Tech"]
        expectation(for: selected, evaluatedWith: tech)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["topic-4-1"].firstMatch.waitForExistence(timeout: 5))

        app.swipeRight(velocity: .slow)
        expectation(for: selected, evaluatedWith: ai)
        waitForExpectations(timeout: 8)
        app.swipeRight(velocity: .slow)
        expectation(for: selected, evaluatedWith: main)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(mainAnchor.waitForExistence(timeout: 3))
        XCTAssertEqual(mainAnchor.frame.minY, scrolledY, accuracy: 2)
    }
}
