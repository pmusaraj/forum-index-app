import XCTest

final class SwipeNavigationUITests: XCTestCase {
    @MainActor
    func testFeedbackExplainsContributorRequirement() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launch()
        let settings = app.buttons["Contribution settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let feedback = app.buttons["open-feedback"]
        for _ in 0..<5 {
            if feedback.exists && feedback.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertFalse(feedback.isEnabled)
        let unavailable = XCTAttachment(screenshot: app.screenshot())
        unavailable.name = "Feedback unavailable in Settings"
        unavailable.lifetime = .keepAlways
        add(unavailable)
        XCTAssertTrue(app.staticTexts["Feedback is available to contributors. Enable contributions in Settings to send a message to the app admins."].exists)
    }

    @MainActor
    func testFeedbackDraftSurvivesUnavailableServerAndCanBeRetried() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_AUTO_ENROLL"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_SIGNAL_DEFAULTS"] = "feedback-\(UUID().uuidString)"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_FEEDBACK"] = "1"
        app.launch()
        let settings = app.buttons["Contribution settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let feedback = app.buttons["open-feedback"]
        for _ in 0..<5 {
            if feedback.exists && feedback.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        let optOut = app.buttons["opt-out-contributions"]
        for _ in 0..<3 {
            if optOut.exists && optOut.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(optOut.exists)
        XCTAssertLessThan(feedback.frame.maxY, optOut.frame.minY)
        let position = XCTAttachment(screenshot: app.screenshot())
        position.name = "Feedback above opt out"
        position.lifetime = .keepAlways
        add(position)
        feedback.tap()
        let message = app.descendants(matching: .any)["feedback-message"].firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Feedback form"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let send = app.buttons["send-feedback"]
        XCTAssertFalse(send.isEnabled)
        message.tap()
        message.typeText("I would love a search button for saved topics.")
        send.tap()
        XCTAssertTrue(app.staticTexts["feedback-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(message.value as? String, "I would love a search button for saved topics.")
        app.terminate()
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_FEEDBACK"] = "0"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_FEEDBACK_AVAILABLE"] = "1"
        app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        for _ in 0..<5 {
            if feedback.exists && feedback.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        feedback.tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertEqual(message.value as? String, "I would love a search button for saved topics.")
        send.tap()
        XCTAssertTrue(app.staticTexts["Thanks for your feedback"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testForYouDefaultOrderAndSavedVisibility() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_AUTO_ENROLL"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_FOR_YOU_ELIGIBLE"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_SIGNAL_DEFAULTS"] = "feed-eligibility-\(UUID().uuidString)"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()
        let forYou = app.buttons["For You"]
        let trending = app.buttons["Trending"]
        XCTAssertTrue(forYou.waitForExistence(timeout: 15))
        XCTAssertEqual(forYou.value as? String, "Selected")
        XCTAssertLessThan(forYou.frame.minX, trending.frame.minX)
        XCTAssertLessThan(trending.frame.minX, app.buttons["AI"].frame.minX)

        app.buttons["Customize subjects"].tap()
        let toggle = app.buttons["subject-toggle-for-you-feed"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(trending.waitForExistence(timeout: 5))
        XCTAssertFalse(forYou.exists)
        XCTAssertEqual(trending.value as? String, "Selected")

        app.terminate()
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "0"
        app.launch()
        XCTAssertTrue(trending.waitForExistence(timeout: 15))
        XCTAssertFalse(forYou.exists)
        XCTAssertEqual(trending.value as? String, "Selected")
    }

    @MainActor
    func testIneligibleReadersStartWithTrending() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Trending"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["Trending"].value as? String, "Selected")
        XCTAssertFalse(app.buttons["For You"].exists)
        app.buttons["Customize subjects"].tap()
        XCTAssertTrue(app.buttons["subject-toggle-main-feed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["subject-toggle-for-you-feed"].exists)
    }

    @MainActor
    func testAutomaticEnrollmentAndPersistentOptOut() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_AUTO_ENROLL"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_SIGNAL_DEFAULTS"] = "auto-enrollment-\(UUID().uuidString)"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_DEVICE_NAME"] = "1"
        app.launch()
        let settings = app.buttons["Contribution settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Public contributor"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["enable-contributions"].exists)
        XCTAssertEqual(app.textFields["contribution-device-name"].value as? String, "iPhone")
        let optOut = app.buttons["opt-out-contributions"]
        for _ in 0..<3 {
            if optOut.exists && optOut.isHittable { break }
            app.swipeUp()
        }
        optOut.tap()
        app.buttons["Opt out"].tap()
        XCTAssertTrue(app.buttons["enable-contributions"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let enable = app.buttons["enable-contributions"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5))
        XCTAssertTrue(enable.isEnabled)
        XCTAssertFalse(app.textFields["contribution-display-name"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Manual-contribution-button"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        enable.tap()
        XCTAssertTrue(app.staticTexts["Public contributor"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testScrollingTopicsKeepsHeaderVisible() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()

        let title = app.staticTexts["reader-title"]
        let main = app.buttons["Trending"]
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
        XCTAssertFalse(app.staticTexts["Technology"].exists)
        XCTAssertEqual(app.buttons["subject-toggle-parent:sport"].value as? String, "Checked")
        let mainToggle = app.buttons["subject-toggle-main-feed"]
        XCTAssertEqual(mainToggle.value as? String, "Checked")
        mainToggle.tap()
        app.buttons["Done"].tap()

        XCTAssertFalse(app.buttons["Trending"].exists)
        let ai = app.buttons["AI"]
        XCTAssertTrue(ai.waitForExistence(timeout: 3))
        XCTAssertEqual(ai.value as? String, "Selected")
        XCTAssertTrue(app.buttons["topic-2-1"].firstMatch.waitForExistence(timeout: 5))

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FORUM_INDEX_UI_TEST_RESET_SUBJECTS")
        app.launchEnvironment.removeValue(forKey: "FORUM_INDEX_UI_TEST_SLOW_FEED")
        app.launch()
        XCTAssertTrue(app.buttons["AI"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Trending"].exists)
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
        XCTAssertLessThan(app.buttons["AI"].frame.minX, app.buttons["Trending"].frame.minX)
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
        XCTAssertTrue(app.buttons["Trending"].waitForExistence(timeout: 15))
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
        XCTAssertTrue(app.buttons["Trending"].waitForExistence(timeout: 15))
        app.swipeLeft(velocity: .slow)
        XCTAssertEqual(app.buttons["topic-2-1"].firstMatch.value as? String, "Opened")
    }

    @MainActor
    func testPagerSettlesOnAFullWidthPageAfterRepeatedSwipes() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["Trending"].waitForExistence(timeout: 15))
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
        app.buttons["Trending"].tap()
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
    func testTopicSheetHasRightSideIconOnlyShareStarAndDismissActionsAndStarPersists() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_BOOKMARKS"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["Trending"].waitForExistence(timeout: 15))
        app.swipeLeft(velocity: .slow)

        let topic = app.buttons["topic-2-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        topic.tap()

        let share = app.buttons["Share topic"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Open in Safari"].exists)
        XCTAssertFalse(app.buttons["topic-signal-up"].exists)
        XCTAssertFalse(app.buttons["topic-signal-down"].exists)
        let star = app.buttons["topic-web-star"]
        let dismiss = app.buttons["Dismiss topic"]
        XCTAssertTrue(star.exists)
        XCTAssertTrue(dismiss.exists)
        XCTAssertGreaterThan(share.frame.minX, app.frame.midX)
        XCTAssertEqual(share.frame.midX, star.frame.midX, accuracy: 2)
        XCTAssertEqual(star.frame.midX, dismiss.frame.midX, accuracy: 2)
        XCTAssertGreaterThan(star.frame.minY, share.frame.maxY)
        XCTAssertGreaterThan(dismiss.frame.minY, star.frame.maxY)
        for button in [share, star, dismiss] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertLessThanOrEqual(button.frame.width, 64)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            XCTAssertLessThanOrEqual(button.frame.height, 64)
        }
        star.tap()
        expectation(for: NSPredicate(format: "label == %@", "Remove bookmark"), evaluatedWith: star)
        waitForExpectations(timeout: 3)
        app.buttons["Dismiss topic"].tap()

        let showStarred = app.buttons["Show bookmarks"]
        XCTAssertTrue(showStarred.waitForExistence(timeout: 3))
        showStarred.tap()
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
    func testTopicListHidesStarAndLongPressOffersStarAndReports() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_BOOKMARKS"] = "1"
        app.launch()

        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["topic-star-1-1"].exists)
        topic.press(forDuration: 1)

        XCTAssertTrue(app.buttons["topic-context-star"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["topic-context-upvote"].exists)
        XCTAssertFalse(app.buttons["topic-context-downvote"].exists)
        XCTAssertTrue(app.buttons["Report"].exists)
        app.buttons["Report"].tap()
        XCTAssertTrue(app.buttons["Low quality"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Inappropriate"].exists)
        XCTAssertTrue(app.buttons["Wrong subject"].exists)
    }

    @MainActor
    func testReportingWhileNotEnrolledOpensContributions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_BOOKMARKS"] = "1"
        app.launch()

        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.press(forDuration: 1)
        app.buttons["Report"].tap()
        let lowQuality = app.buttons["Low quality"]
        XCTAssertTrue(lowQuality.waitForExistence(timeout: 3))
        lowQuality.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFailedReportShowsAlert() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_ENROLLED"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_FAIL_ACTION"] = "1"
        app.launch()

        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.press(forDuration: 1)
        app.buttons["Report"].tap()
        app.buttons["Low quality"].tap()

        XCTAssertTrue(app.alerts["Report failed"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Couldn’t report this contribution."].exists)
    }

    @MainActor
    func testURLLessTopicCannotBeStarredFromContextMenu() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_URLLESS_TOPIC"] = "1"
        app.launch()

        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.press(forDuration: 1)

        XCTAssertFalse(app.buttons["topic-context-star"].exists)
        XCTAssertTrue(app.buttons["Report"].exists)
    }

    @MainActor
    func testTabsStayFixedAndSelectedTabScrollsIntoView() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launch()

        let main = app.buttons["Trending"]
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

        let main = app.buttons["Trending"]
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

        let main = app.buttons["Trending"]
        let ai = app.buttons["AI"]
        let mainAnchor = app.buttons["topic-1-8"].firstMatch
        XCTAssertTrue(mainAnchor.waitForExistence(timeout: 15))
        let initialY = mainAnchor.frame.minY

        // Keep the anchor on screen: a full-screen swipe can scroll it out of
        // the lazy list's accessibility tree before its position is recorded.
        let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd, withVelocity: .slow, thenHoldForDuration: 0.2)
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

    @MainActor
    func testTrustedSettingsShowForumSubmission() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_ENROLLED"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_TRUSTED"] = "1"
        app.launch()

        let settings = app.buttons["Contribution settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["main-feed-personalization-description"].exists)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Settings overview"
        overview.lifetime = .keepAlways
        add(overview)
        for _ in 0..<5 {
            if app.textFields["forum-submission-url"].exists && app.textFields["forum-submission-url"].isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        }
        XCTAssertTrue(app.staticTexts["Recommend a forum"].exists)
        XCTAssertTrue(app.textFields["forum-submission-url"].exists)
        XCTAssertTrue(app.buttons["submit-forum"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Reads, star changes")).firstMatch.exists)
        let details = XCTAttachment(screenshot: app.screenshot())
        details.name = "Settings information"
        details.lifetime = .keepAlways
        add(details)
    }

    @MainActor
    func testContributionsShowsTransparencyStatusAndConfirmedOptOut() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_ENROLLED"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_DEVICE_NAME"] = "1"
        app.launch()

        let settings = app.buttons["Contribution settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Contributor status"].exists)
        XCTAssertFalse(app.staticTexts["Device code: A7K-29Q"].exists)
        XCTAssertTrue(app.staticTexts["Public contributor"].exists)
        XCTAssertTrue(app.staticTexts["Apple verified"].exists)
        let deviceName = app.textFields["contribution-device-name"]
        XCTAssertTrue(deviceName.exists)
        XCTAssertEqual(deviceName.value as? String, "iPhone")
        deviceName.tap()
        deviceName.typeText(" 17 Pro Max")
        let saveDeviceName = app.buttons["save-device-name"]
        XCTAssertTrue(saveDeviceName.isEnabled)
        app.buttons["Done"].tap()
        settings.tap()
        let unsavedDeviceName = app.textFields["contribution-device-name"]
        XCTAssertTrue(unsavedDeviceName.waitForExistence(timeout: 3))
        XCTAssertEqual(unsavedDeviceName.value as? String, "iPhone")
        unsavedDeviceName.tap()
        unsavedDeviceName.typeText(" 17 Pro Max")
        saveDeviceName.tap()
        XCTAssertEqual(unsavedDeviceName.value as? String, "iPhone 17 Pro Max")
        app.buttons["Done"].tap()
        settings.tap()
        let persistedDeviceName = app.textFields["contribution-device-name"]
        XCTAssertTrue(persistedDeviceName.waitForExistence(timeout: 3))
        XCTAssertEqual(persistedDeviceName.value as? String, "iPhone 17 Pro Max")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Reads, star changes")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Upvotes"].exists)
        XCTAssertFalse(app.staticTexts["Downvotes"].exists)
        XCTAssertFalse(app.staticTexts["Bookmark changes"].exists)
        XCTAssertFalse(app.staticTexts["Ranking impact"].exists)

        let optOut = app.buttons["opt-out-contributions"]
        if !optOut.exists { app.swipeUp() }
        XCTAssertTrue(optOut.waitForExistence(timeout: 3))
        optOut.tap()
        XCTAssertTrue(app.staticTexts["Opt out of contributions?"].waitForExistence(timeout: 3))
        let confirmOptOut = app.buttons["Opt out"]
        XCTAssertTrue(confirmOptOut.waitForExistence(timeout: 3))
        confirmOptOut.tap()
        XCTAssertTrue(app.buttons["enable-contributions"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields.matching(identifier: "contribution-device-name").count, 1)
        XCTAssertEqual(app.textFields["contribution-device-name"].value as? String, "iPhone 17 Pro Max")
        XCTAssertFalse(app.staticTexts["Device"].exists)
        app.buttons["Done"].tap()
        settings.tap()
        XCTAssertTrue(app.textFields["contribution-device-name"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["contribution-device-name"].value as? String, "iPhone 17 Pro Max")
        XCTAssertFalse(app.staticTexts["Device"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Opted-out-saved-device-name"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
