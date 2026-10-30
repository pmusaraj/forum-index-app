import XCTest

final class ReaderTypographyUITests: XCTestCase {
    @MainActor
    func testTypographySettingUpdatesReaderAndPersists() throws {
        let prose = String(repeating: "Readable text should respond immediately to the chosen typography. ", count: 5).trimmingCharacters(in: .whitespaces)
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_TYPOGRAPHY"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = "# Typography\n\n\(prose)\n\n## Summary\n\nA short summary."
        app.launch()
        app.activate()
        if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 20))
        topic.click()
        let paragraph = app.staticTexts.matching(NSPredicate(format: "value == %@", prose)).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        let compactHeight = paragraph.frame.height

        app.buttons["mac-sidebar-settings"].click()
        let picker = app.descendants(matching: .any)["typography-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(picker.frame.minY, app.descendants(matching: .any)["appearance-picker"].firstMatch.frame.minY)
        XCTAssertTrue(app.staticTexts["Color scheme"].exists)
        func choice(_ name: String) -> XCUIElement {
            let radio = app.radioButtons[name].firstMatch
            return radio.exists ? radio : app.buttons[name].firstMatch
        }
        func isSelected(_ element: XCUIElement) -> Bool {
            element.isSelected || (element.value as? NSNumber)?.boolValue == true || element.value as? String == "1"
        }
        XCTAssertTrue(isSelected(choice("Compact")), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "macOS typography settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        choice("Spacious").click()
        XCTAssertTrue(isSelected(choice("Spacious")))
        app.buttons["Done"].firstMatch.click()
        let grew = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in paragraph.frame.height > compactHeight }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [grew], timeout: 5), .completed)

        app.terminate()
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_TYPOGRAPHY"] = nil
        app.launch()
        app.activate()
        if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
        XCTAssertTrue(app.buttons["mac-sidebar-settings"].waitForExistence(timeout: 15))
        app.buttons["mac-sidebar-settings"].click()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(isSelected(choice("Spacious")))
        choice("Compact").click()
        XCTAssertTrue(isSelected(choice("Compact")))
        app.buttons["Done"].firstMatch.click()
        topic.click()
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        XCTAssertEqual(paragraph.frame.height, compactHeight, accuracy: 1)
    }

    @MainActor
    func testNativeTypographyComparisons() throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Typography")
        let feed = try String(contentsOf: fixtures.appendingPathComponent("feed.json"), encoding: .utf8)
        var expectedWindow: CGRect?
        var expectedReader: CGRect?

        for style in ["spacious", "compact"] {
            for (name, topicID, bodyText) in [
                ("ansible", "topic-1-46563", "Following the adoption"),
                ("nvidia", "topic-2-387395", "I am quantizing")
            ] {
                let app = XCUIApplication()
                app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
                app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
                app.launchEnvironment["FORUM_INDEX_UI_TEST_TYPOGRAPHY_CAPTURE"] = "1"
                app.launchEnvironment["FORUM_INDEX_UI_TEST_FEED"] = feed
                app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = try String(
                    contentsOf: fixtures.appendingPathComponent("\(name).md"), encoding: .utf8)
                app.launchArguments = ["-appearance-mode", "light", "-reader-typography", style]
                app.launch()
                app.activate()
                if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
                let topic = app.buttons[topicID].firstMatch
                XCTAssertTrue(topic.waitForExistence(timeout: 20))
                topic.click()
                let title = app.descendants(matching: .any)["topic-preview-title"].firstMatch
                XCTAssertTrue(title.waitForExistence(timeout: 15))
                let body = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", bodyText)).firstMatch
                XCTAssertTrue(body.waitForExistence(timeout: 10))
                let window = app.windows.firstMatch
                let reader = app.descendants(matching: .any)["topic-markdown-preview"].firstMatch
                if let expectedWindow, let expectedReader {
                    XCTAssertEqual(window.frame.width, expectedWindow.width, accuracy: 1)
                    XCTAssertEqual(window.frame.height, expectedWindow.height, accuracy: 1)
                    XCTAssertEqual(reader.frame.width, expectedReader.width, accuracy: 1)
                } else {
                    expectedWindow = window.frame
                    expectedReader = reader.frame
                }
                print("TYPOGRAPHY \(name) \(style): window=\(window.frame), reader=\(reader.frame)")
                let screenshot = XCTAttachment(screenshot: window.screenshot())
                screenshot.name = "\(name)-\(style)-top"
                screenshot.lifetime = .keepAlways
                add(screenshot)

                app.terminate()
            }
        }
    }
}
