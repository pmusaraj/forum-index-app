import XCTest
import UIKit

final class TopicNavigationUITests: XCTestCase {
    @MainActor
    func testReaderFillsScreenBeforeAndAfterFeedbackKeyboard() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_AUTO_ENROLL"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_SIGNAL_DEFAULTS"] = "viewport-\(UUID().uuidString)"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_FEEDBACK"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_PAGING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = (1...40).map { "Paragraph \($0). Reader content fills the screen." }.joined(separator: "\n\n")
        app.launch()
        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        assertFullReaderViewport(app, name: "Reader before Settings")
        app.buttons["Dismiss topic"].tap()
        app.buttons["Contribution settings"].tap()
        let feedback = app.buttons["open-feedback"]
        for _ in 0..<5 {
            if feedback.exists && feedback.isHittable { break }
            app.swipeUp()
        }
        feedback.tap()
        let message = app.textFields["feedback-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.tap()
        message.typeText("Viewport regression check")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        topic.tap()
        assertFullReaderViewport(app, name: "Reader after Feedback keyboard")
        app.swipeUp()
        app.swipeUp()
        app.swipeDown()
        assertFullReaderViewport(app, name: "Reader after scrolling")
        swipeContent(app, left: true)
        assertFullReaderViewport(app, name: "Reader after paging")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Dismiss topic"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        assertFullReaderViewport(app, name: "Reader after rotation")
        app.buttons["Dismiss topic"].tap()
        app.buttons["Contribution settings"].tap()
        for _ in 0..<5 {
            if feedback.exists && feedback.isHittable { break }
            app.swipeUp()
        }
        feedback.tap()
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.tap()
        message.typeText("Dismiss sheet with keyboard open")
        for _ in 0..<2 {
            let bar = app.navigationBars["Feedback"]
            if !bar.exists { break }
            bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        topic.tap()
        assertFullReaderViewport(app, name: "Reader after dismissing Feedback sheet")
    }

    @MainActor
    private func assertFullReaderViewport(_ app: XCUIApplication, name: String) {
        let reader = app.scrollViews["topic-markdown-preview"].firstMatch
        XCTAssertTrue(reader.waitForExistence(timeout: 10))
        let dismiss = app.buttons["Dismiss topic"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertEqual(reader.frame.maxY, app.frame.maxY, accuracy: 2, name)
        XCTAssertLessThan(app.frame.maxY - dismiss.frame.maxY, 100, name)
    }

    /// Run with the simulator in Dark appearance. A light site header must only
    /// change status-bar contrast, leaving CSS media queries and the reader dark.
    @MainActor
    func testDarkWebsiteKeepsThemeWithLightHeader() throws {
        try XCTSkipUnless(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.traitCollection.userInterfaceStyle == .dark, "Requires Dark simulator appearance")
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body { margin: 0; font: 20px system-ui; }
        header { background: white; color: black; padding: 20px; }
        main { padding: 20px; }
        .dark { display: none; }
        @media (prefers-color-scheme: dark) {
          .light { display: none; } .dark { display: block; }
        }
        </style></head><body><header>Light website header</header>
        <main><p class="dark">Dark website appearance</p>
        <p class="light">Light website appearance</p></main></body></html>
        """
        app.launch()
        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        let dark = app.webViews.staticTexts["Dark website appearance"]
        XCTAssertTrue(dark.waitForExistence(timeout: 10))
        // Wait until the header observer and native appearance updates settle.
        let remainsDark = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: dark)
        remainsDark.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [remainsDark], timeout: 3), .completed)
        XCTAssertFalse(app.webViews.staticTexts["Light website appearance"].exists)
        app.buttons["Dismiss topic"].firstMatch.tap()
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dark-reader-after-light-website-header"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testWebsiteHeaderStaysInsideViewportAfterScrolling() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body { margin: 0; background: #dceef8; }
        button { position: fixed; top: 0; left: 0; width: 100%; height: 48px; }
        main { padding-top: 70px; height: 3000px; }
        </style></head><body><button>Website header</button>
        <main><p>Start of page</p><p style="margin-top: 600px">Further down</p></main></body></html>
        """
        app.launch()
        let topic = app.buttons["topic-1-1"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        let webView = app.webViews.firstMatch
        let header = webView.buttons["Website header"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let initialY = header.frame.minY
        XCTAssertGreaterThan(webView.frame.minY, app.frame.minY + 20)
        XCTAssertGreaterThanOrEqual(initialY, webView.frame.minY)
        let start = webView.staticTexts["Start of page"]
        let startY = start.frame.minY
        webView.swipeUp()
        XCTAssertTrue(!start.exists || start.frame.minY < startY - 20)
        XCTAssertEqual(header.frame.minY, initialY, accuracy: 2)
        XCTAssertTrue(header.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Website-header-after-scrolling"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

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
        XCTAssertEqual(app.webViews.firstMatch.frame.maxY, app.frame.maxY, accuracy: 1,
                       "Web content should extend through the bottom safe area")
        swipeContent(app, left: true)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        let row = app.buttons["topic-1-2"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isSelected)
    }

    @MainActor
    func testLateWebHeaderColorsTopAndContentReachesBottom() {
        let app = launchReader(markdown: false, html: """
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body { margin: 0; background: rgb(240,240,240); }
        header { height: 80px; background: rgb(55,55,55); color: white; }
        main { height: 2000px; }</style>
        <main>Web layout fixture</main>
        <script>setTimeout(() => {
            const header = document.createElement('header');
            header.textContent = 'Late site header';
            document.body.prepend(header);
        }, 1000);</script>
        """)
        XCTAssertTrue(app.buttons["topic-1-1"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["topic-1-1"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Late site header"].firstMatch.waitForExistence(timeout: 10))
        let matched = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                self.pixel(app.screenshot().image, x: 0.02, y: 0.02) == [55, 55, 55, 255]
            }
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [matched], timeout: 5), .completed)
        let screenshot = app.screenshot()
        XCTAssertEqual(pixel(screenshot.image, x: 0.02, y: 0.12), [55, 55, 55, 255])
        XCTAssertEqual(pixel(screenshot.image, x: 0.02, y: 0.98), [240, 240, 240, 255])
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pixel(_ image: UIImage, x: Double, y: Double) -> [UInt8] {
        guard let source = image.cgImage,
              let sample = source.cropping(to: CGRect(x: Int(Double(source.width) * x),
                                                      y: Int(Double(source.height) * y), width: 1, height: 1)) else { return [] }
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes
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
    private func launchReader(markdown: Bool = true, html: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_HTML"] = html
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
