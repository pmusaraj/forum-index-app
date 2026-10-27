import XCTest

/// Explicitly opt in: these captures are local App Store assets, not regression tests.
final class AppStoreScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FORUM_INDEX_CAPTURE_SCREENSHOTS"] == "1")
        continueAfterFailure = false
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchEnvironment = [
                "FORUM_INDEX_UI_TESTING": "1",
                "FORUM_INDEX_UI_TEST_RESET_SUBJECTS": "1",
                "FORUM_INDEX_UI_TEST_RESET_BOOKMARKS": "1",
                "FORUM_INDEX_UI_TEST_RESET_OPENED_TOPICS": "1",
                "FORUM_INDEX_UI_TEST_FEED": try fixture("Feed", extension: "json"),
                "FORUM_INDEX_UI_TEST_TAXONOMY": try fixture("Subjects", extension: "json"),
                "FORUM_INDEX_UI_TEST_MARKDOWN": try fixture("Reader", extension: "md"),
                "FORUM_INDEX_UI_TEST_FORUM_DETAIL": try fixture("Forum", extension: "json")
            ]
            app.launch()
            let first = app.buttons["topic-952-105238"].firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 20))
            app.buttons["Contribution settings"].tap()
            let picker = app.segmentedControls["appearance-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.buttons[appearance].tap()
            app.buttons["Done"].firstMatch.tap()
            capture(app, "01-discover", appearance)

            app.buttons["topic-674-103187"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts["topic-preview-title"].waitForExistence(timeout: 15))
            capture(app, "02-reader", appearance)
            app.buttons["Bookmark topic"].tap()
            app.buttons["topic-header-forum-overview"].tap()
            XCTAssertTrue(app.buttons["forum-overview-forum-link"].waitForExistence(timeout: 10))
            capture(app, "03-community", appearance)
            // A tap outside the popover dismisses it on both device families.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
            app.buttons["Dismiss topic"].firstMatch.tap()

            for identifier in ["topic-952-105238", "topic-961-103830", "topic-1131-103320", "topic-1133-103321", "topic-999-105303"] {
                let row = app.buttons[identifier].firstMatch
                if row.exists && row.isHittable {
                    row.press(forDuration: 1)
                    let star = app.buttons["topic-context-star"].firstMatch
                    XCTAssertTrue(star.waitForExistence(timeout: 5))
                    star.tap()
                }
            }
            app.buttons["Show bookmarks"].tap()
            XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
            capture(app, "04-starred", appearance)
            app.buttons["Done"].firstMatch.tap()
            app.buttons["Customize subjects and feeds"].tap()
            XCTAssertTrue(app.navigationBars["Subjects"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Hide Main"].isHittable)
            capture(app, "05-subjects", appearance)
            app.terminate()
        }
    }

    @MainActor
    func testCaptureBookmarksReview() throws {
        continueAfterFailure = false
        for appearance in ["Light", "Dark"] {
            let app = XCUIApplication()
            app.launchEnvironment = [
                "FORUM_INDEX_UI_TESTING": "1",
                "FORUM_INDEX_UI_TEST_RESET_SUBJECTS": "1",
                "FORUM_INDEX_UI_TEST_RESET_BOOKMARKS": "1",
                "FORUM_INDEX_UI_TEST_FEED": try fixture("Feed", extension: "json"),
                "FORUM_INDEX_UI_TEST_TAXONOMY": try fixture("Subjects", extension: "json")
            ]
            app.launch()
            XCTAssertTrue(app.buttons["topic-952-105238"].firstMatch.waitForExistence(timeout: 20))
            app.buttons["Contribution settings"].tap()
            let picker = app.segmentedControls["appearance-picker"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.buttons[appearance].tap()
            app.buttons["Done"].firstMatch.tap()
            for identifier in ["topic-952-105238", "topic-674-103187", "topic-961-103830"] {
                let row = app.buttons[identifier].firstMatch
                if row.exists && row.isHittable {
                    row.press(forDuration: 1)
                    let bookmark = app.buttons["topic-context-star"].firstMatch
                    XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
                    bookmark.tap()
                }
            }
            app.buttons["Show bookmarks"].tap()
            XCTAssertTrue(app.navigationBars["Bookmarks"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["bookmark-tracking-note"].isHittable)
            capture(app, "bookmarks-review", appearance)
            app.terminate()
        }
    }

    private func fixture(_ name: String, extension suffix: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: suffix,
                                                         subdirectory: "Fixtures/AppStore"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String, _ appearance: String) {
        // Allow presentation animations and remotely loaded forum icons to settle.
        Thread.sleep(forTimeInterval: 3)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "appstore-\(appearance.lowercased())-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
