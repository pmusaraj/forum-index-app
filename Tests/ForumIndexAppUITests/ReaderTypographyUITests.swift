import XCTest

final class ReaderTypographyUITests: XCTestCase {
    @MainActor
    func testTypographySettingPersistsAndScalesReader() {
        let prose = String(repeating: "Readable text should respond immediately to the chosen typography. ", count: 3).trimmingCharacters(in: .whitespaces)
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_TYPOGRAPHY"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = "# Typography\n\n\(prose)\n\n## Summary\n\nA short summary."
        app.launch()
        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 20))
        topic.tap()
        let paragraph = app.staticTexts.matching(NSPredicate(format: "label == %@", prose)).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        let compactHeight = paragraph.frame.height
        app.buttons["Dismiss topic"].firstMatch.tap()
        app.buttons["Contribution settings"].tap()
        let picker = app.segmentedControls["typography-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Color scheme"].exists)
        XCTAssertTrue(app.staticTexts["Typography"].exists)
        XCTAssertTrue(picker.buttons["Compact"].isSelected)
        XCTAssertGreaterThan(picker.frame.minY, app.segmentedControls["appearance-picker"].frame.minY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "iOS typography settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        picker.buttons["Spacious"].tap()
        XCTAssertTrue(picker.buttons["Spacious"].isSelected)
        app.buttons["Done"].firstMatch.tap()
        topic.tap()
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(paragraph.frame.height, compactHeight)
        let spaciousHeight = paragraph.frame.height

        app.terminate()
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_TYPOGRAPHY"] = nil
        app.launch()
        XCTAssertTrue(app.buttons["Contribution settings"].waitForExistence(timeout: 15))
        app.buttons["Contribution settings"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["Spacious"].isSelected)
        app.buttons["Done"].firstMatch.tap()
        topic.tap()
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        XCTAssertEqual(paragraph.frame.height, spaciousHeight, accuracy: 1)

        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(paragraph.frame.height, spaciousHeight)
        XCTAssertLessThanOrEqual(paragraph.frame.width, app.windows.firstMatch.frame.width)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Contribution settings"].waitForExistence(timeout: 15))
        app.buttons["Contribution settings"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Compact"].tap()
        XCTAssertTrue(picker.buttons["Compact"].isSelected)
        app.buttons["Done"].firstMatch.tap()
        topic.tap()
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        XCTAssertEqual(paragraph.frame.height, compactHeight, accuracy: 1)
    }
}
