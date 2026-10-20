import XCTest

final class MacReaderUITests: XCTestCase {
    @MainActor
    func testBookmarkShortcutTracksCurrentTopicAndTextFocus() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = "# Bookmark shortcut\n\nClick this text and press B to toggle the bookmark."
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = "<html><body><input aria-label='Reply' type='text'></body></html>"
        app.launch()
        app.activate()
        if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
        let topic = app.buttons["topic-1-1"].firstMatch
        guard topic.waitForExistence(timeout: 20) else { XCTFail(app.debugDescription); return }
        topic.click()
        let bookmark = app.buttons["topic-web-star"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        let initialValue = bookmark.value as? String
        let changedValue = initialValue == "Bookmarked" ? "Not bookmarked" : "Bookmarked"
        app.typeKey("b", modifierFlags: [])
        let toggled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", changedValue), object: bookmark)
        XCTAssertEqual(XCTWaiter.wait(for: [toggled], timeout: 5), .completed)
        let article = app.descendants(matching: .any)["topic-markdown-preview"].firstMatch
        article.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).click()
        app.typeKey("b", modifierFlags: [])
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", initialValue ?? ""), object: bookmark)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        if bookmark.value as? String != "Bookmarked" { bookmark.click() }
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "Accent-colored bookmarked topic"
        shot.lifetime = .keepAlways
        add(shot)
        if initialValue != "Bookmarked" { bookmark.click() }
        app.buttons["topic-header-full-html"].click()
        let field = app.webViews.textFields["Reply"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.click()
        field.typeText("bookmarks")
        XCTAssertEqual(field.value as? String, "bookmarks")
        XCTAssertEqual(bookmark.value as? String, initialValue)
    }

    @MainActor
    func testSpaceScrollsMarkdownTopic() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = (1...60).map {
            "Paragraph \($0). A long conversation that should scroll when the Space key is pressed."
        }.joined(separator: "\n\n")
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = "<html><body>Website</body></html>"
        app.launch()
        app.activate()
        if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
        let topic = app.buttons["topic-1-1"].firstMatch
        guard topic.waitForExistence(timeout: 20) else { XCTFail(app.debugDescription); return }
        topic.click()
        let title = app.descendants(matching: .any)["topic-preview-title"].firstMatch
        guard title.waitForExistence(timeout: 10) else { XCTFail(app.debugDescription); return }
        XCTAssertTrue(title.isHittable)
        func checkPageScroll() {
            app.typeKey(.space, modifierFlags: [])
            let scrolled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !title.isHittable }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [scrolled], timeout: 5), .completed)
            app.typeKey(.space, modifierFlags: .shift)
            let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in title.isHittable }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 5), .completed)
        }
        checkPageScroll()
        let article = app.descendants(matching: .any)["topic-markdown-preview"].firstMatch
        article.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        checkPageScroll()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(app.buttons["topic-1-2"].isSelected)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        checkPageScroll()
        app.buttons["topic-header-full-html"].click()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["Navigate"].click()
        XCTAssertFalse(app.menuItems["Scroll Down a Page"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        app.buttons["topic-header-full-html"].click()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        checkPageScroll()
    }

    @MainActor
    func testWindowControlsAndStableColumns() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = "<html><body>A topic</body></html>"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = "# Topic layout\n\nOpening a topic should not move the sidebar."
        app.launch()
        app.activate()
        if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
        let topic = app.buttons["topic-1-1"].firstMatch
        guard topic.waitForExistence(timeout: 20) else { XCTFail(app.debugDescription); return }
        let window = app.windows.firstMatch
        let sidebar = app.scrollViews["mac-sidebar-subjects"]
        let initialSidebar = sidebar.frame
        let initialTopic = topic.frame
        print("COLUMN EMPTY sidebar=\(initialSidebar) topic=\(initialTopic)")
        let emptyShot = XCTAttachment(screenshot: window.screenshot())
        emptyShot.name = "Empty reader columns"
        emptyShot.lifetime = .keepAlways
        add(emptyShot)
        topic.click()
        XCTAssertTrue(app.buttons["topic-header-full-html"].waitForExistence(timeout: 10))
        print("COLUMN SELECTED sidebar=\(sidebar.frame) topic=\(topic.frame)")
        let selectedShot = XCTAttachment(screenshot: window.screenshot())
        selectedShot.name = "Selected reader columns"
        selectedShot.lifetime = .keepAlways
        add(selectedShot)
        XCTAssertEqual(sidebar.frame.width, initialSidebar.width, accuracy: 1)
        XCTAssertEqual(topic.frame.minX, initialTopic.minX, accuracy: 1)
        XCTAssertEqual(topic.frame.width, initialTopic.width, accuracy: 1)
        XCTAssertTrue(window.buttons[XCUIIdentifierCloseWindow].isHittable)
        XCTAssertTrue(window.buttons[XCUIIdentifierMinimizeWindow].isHittable)
        XCTAssertTrue(window.buttons[XCUIIdentifierFullScreenWindow].isHittable)
        app.buttons["Dismiss topic"].click()
        XCTAssertEqual(sidebar.frame.width, initialSidebar.width, accuracy: 1)
        XCTAssertEqual(topic.frame.width, initialTopic.width, accuracy: 1)
    }

    @MainActor
    func testTopInsetAndSidebarToggle() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = "<html><body style='margin:0'><h1 style='margin:0'>Top of website</h1></body></html>"
        app.launch()
        app.activate()
        if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
        let topic = app.buttons["topic-1-1"].firstMatch
        guard topic.waitForExistence(timeout: 20) else { XCTFail(app.debugDescription); return }
        topic.click()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        print("LAYOUT TEST window=\(window.frame) web=\(web.frame) logo=\(app.staticTexts["mac-sidebar-logo"].frame)")
        let shot = XCTAttachment(screenshot: window.screenshot())
        shot.name = "Window top inset"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertLessThanOrEqual(web.frame.minY - window.frame.minY, 2)
        XCTAssertLessThanOrEqual(app.staticTexts["mac-sidebar-logo"].frame.minY - window.frame.minY, 41)
        let toggle = app.buttons["Hide Sidebar"]
        XCTAssertTrue(toggle.isHittable)
        XCTAssertLessThanOrEqual(toggle.frame.minY - window.frame.minY, 12)
        toggle.click()
        XCTAssertTrue(app.buttons["Show Sidebar"].waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons[XCUIIdentifierCloseWindow].isHittable)
        XCTAssertFalse(window.buttons[XCUIIdentifierFullScreenWindow].frame.intersects(app.buttons["Show Sidebar"].frame))
        app.buttons["Show Sidebar"].click()
        XCTAssertTrue(app.buttons["mac-sidebar-settings"].isHittable)
    }

    @MainActor
    func testMarkdownReaderStartsAtWindowTop() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = "# Reading at the top\n\nThe reader should start at the window edge."
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = "<html><body>Website view</body></html>"
        app.launch()
        app.activate()
        if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
        let topic = app.buttons["topic-1-1"].firstMatch
        guard topic.waitForExistence(timeout: 20) else { XCTFail(app.debugDescription); return }
        topic.click()
        let header = app.buttons["topic-header-forum-overview"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        XCTAssertLessThanOrEqual(header.frame.minY - window.frame.minY, 2)
        let shot = XCTAttachment(screenshot: window.screenshot())
        shot.name = "Markdown reader without top inset"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testKeyboardTopicAndSubjectNavigation() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = "# Keyboard reading\n\nA conversation."
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = "<html><body>Original forum page</body></html>"
        app.launch()
        app.activate()
        if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
        guard app.buttons["topic-1-1"].waitForExistence(timeout: 20) else {
            XCTFail(app.debugDescription)
            return
        }

        func assertSelected(_ id: String) {
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"),
                                                     object: app.buttons[id])
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        }

        app.typeKey(.upArrow, modifierFlags: [])
        assertSelected("topic-1-1")
        app.typeKey(.downArrow, modifierFlags: [])
        assertSelected("topic-1-2")
        app.typeKey(.upArrow, modifierFlags: [])
        assertSelected("topic-1-1")
        app.typeKey(.upArrow, modifierFlags: [])
        assertSelected("topic-1-1")

        app.typeKey(.downArrow, modifierFlags: .command)
        XCTAssertTrue(app.buttons["topic-2-1"].waitForExistence(timeout: 5))
        app.typeKey(.downArrow, modifierFlags: [])
        assertSelected("topic-2-1")
        let readerSwitch = app.buttons["topic-header-full-html"]
        XCTAssertTrue(readerSwitch.waitForExistence(timeout: 5))
        readerSwitch.click()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        app.webViews.firstMatch.click()
        app.typeKey(.downArrow, modifierFlags: [])
        assertSelected("topic-2-2")

        app.typeKey(.upArrow, modifierFlags: .command)
        XCTAssertTrue(app.buttons["topic-1-1"].waitForExistence(timeout: 5))
        app.typeKey(.upArrow, modifierFlags: [])
        assertSelected("topic-1-1")
    }

    @MainActor
    func testInlineReaderAndPinnedSidebarActions() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_BOOKMARKS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = "# A Mac conversation\n\nReading inside the main window."
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = "<html><body>Original forum page</body></html>"
        app.launch()
        app.activate()
        if app.windows.count == 0 { app.typeKey("n", modifierFlags: .command) }
        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 20))
        topic.click()
        XCTAssertTrue(app.buttons["topic-web-star"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertTrue(topic.isHittable)
        XCTAssertTrue(app.buttons["Share topic"].exists)
        let readerSwitch = app.buttons["topic-header-full-html"]
        XCTAssertTrue(readerSwitch.waitForExistence(timeout: 5))
        readerSwitch.click()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        readerSwitch.click()
        app.buttons["topic-web-star"].click()

        let starred = app.buttons["mac-sidebar-starred"]
        let settings = app.buttons["mac-sidebar-settings"]
        XCTAssertTrue(starred.isHittable)
        XCTAssertTrue(settings.isHittable)
        let footerY = starred.frame.minY
        let subjects = app.scrollViews["mac-sidebar-subjects"]
        subjects.swipeUp()
        XCTAssertEqual(starred.frame.minY, footerY, accuracy: 1)
        XCTAssertTrue(settings.isHittable)

        starred.click()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Main fixture topic 1")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.click()
        XCTAssertTrue(app.buttons["topic-web-star"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sheets.count, 0)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Mac three-column reader"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        settings.click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
    }
}
