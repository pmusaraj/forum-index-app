import XCTest

final class BookmarkResumeUITests: XCTestCase {
    @MainActor
    func testResumeLongTopicAndKeepPartialReadPosition() throws {
        let app = try launchLongTopic()
        app.buttons["Show bookmarks"].tap()
        let saved = app.buttons["bookmark-https://example.com/t/long-topic/123"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        let marker = app.staticTexts["topic-first-unread"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        XCTAssertEqual(marker.value as? String, "Post 481")
        XCTAssertTrue(marker.isHittable)
        XCTAssertTrue(app.staticTexts["@author-481"].isHittable)
        XCTAssertFalse(app.staticTexts["@author-1"].exists)
        let preview = app.scrollViews["topic-markdown-preview"]
        for _ in 0..<3 { preview.swipeUp(velocity: .slow) }
        // Leave a reply's bottom in view long enough to record reading progress.
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["Dismiss topic"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.value as? String, "New replies")
        saved.tap()
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        XCTAssertNotEqual(marker.value as? String, "Post 481")
        XCTAssertTrue(marker.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Resume first unread reply in a long topic"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testEarlierRepliesAndBackToBeginning() throws {
        let app = try launchLongTopic()
        app.buttons["Show bookmarks"].tap()
        app.buttons["bookmark-https://example.com/t/long-topic/123"].tap()
        XCTAssertTrue(app.staticTexts["topic-first-unread"].waitForExistence(timeout: 10))
        let preview = app.scrollViews["topic-markdown-preview"]
        // Scrolling back across the loaded boundary should expose page 24, not jump to its start.
        preview.swipeDown(velocity: .slow)
        let previous = app.staticTexts["@author-480"]
        for _ in 0..<4 where !previous.isHittable { preview.swipeDown(velocity: .slow) }
        XCTAssertTrue(previous.isHittable)
        XCTAssertFalse(app.staticTexts["@author-461"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Earlier replies loaded without jumping to the start of the batch"
        shot.lifetime = .keepAlways
        add(shot)
        // A direct route to the original post must not require loading all intervening pages.
        let beginning = app.buttons["Back to top"]
        XCTAssertTrue(beginning.isHittable)
        beginning.tap()
        XCTAssertTrue(app.staticTexts["topic-preview-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Reply 1.")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testFailedResumeCanReturnToBeginningWithoutClearingUnread() throws {
        let app = try launchLongTopic(failsResume: true)
        app.buttons["Show bookmarks"].tap()
        let saved = app.buttons["bookmark-https://example.com/t/long-topic/123"]
        saved.tap()
        XCTAssertTrue(app.buttons["Back to top"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Retry"].exists)
        app.buttons["Back to top"].tap()
        XCTAssertTrue(app.staticTexts["topic-preview-title"].waitForExistence(timeout: 5))
        app.buttons["Dismiss topic"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.value as? String, "New replies")
    }

    @MainActor
    private func launchLongTopic(failsResume: Bool = false) throws -> XCUIApplication {
        let app = XCUIApplication()
        let url = "https://example.com/t/long-topic/123"
        let topic: [String: Any] = ["id": 123, "title": "Long topic", "url": url,
                                  "forum": ["id": 1, "name": "Example", "slug": "example",
                                            "base_url": "https://example.com", "supports_markdown": true]]
        func json(_ object: Any) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        }
        let bookmark: [String: Any] = ["title": "Long topic", "url": url, "forumName": "Example", "topic": topic,
                                       "addedAt": -978307200, "lastReadAt": -978306720,
                                       "latestReplyAt": -978306600, "lastReadPostNumber": 480]
        let formatter = ISO8601DateFormatter()
        let posts = (1...600).map { number -> [String: Any] in
            ["id": number + 1000, "post_number": number,
             "created_at": formatter.string(from: Date(timeIntervalSince1970: Double(number))) ]
        }
        let index: [String: Any] = ["post_stream": ["stream": Array(1001...1600), "posts": posts],
                                   "chunk_size": 20, "last_posted_at": "1970-01-01T00:10:00Z"]
        var pages: [String: String] = [:]
        for page in [1, 24, 25, 26, 27] {
            var markdown = "# Long topic\n\n**URL:** \(url)\n**Page:** \(page)\n\n"
            markdown += (((page - 1) * 20 + 1)...(page * 20)).map { number in
                """
                <div class="post-metadata">
                **Author:** [@author-\(number)](https://example.com/u/author)
                **Post date:** [Date](\(url)/\(number) "\(formatter.string(from: Date(timeIntervalSince1970: Double(number))))")
                </div>

                Reply \(number).

                \(String(repeating: "This is a longer reply with enough text to require deliberate scrolling. Reading should advance the saved position only when its bottom has remained visible.\n\n", count: 5))
                """
            }.joined(separator: "\n\n---\n\n")
            if page > 1 { markdown += "\n\n[Previous page](\(url).md?page=\(page - 1))" }
            markdown += "\n\n[Next page](\(url).md?page=\(page + 1))"
            pages["\(url).md?page=\(page)"] = markdown
        }
        app.launchEnvironment = [
            "FORUM_INDEX_UI_TESTING": "1",
            "FORUM_INDEX_UI_TEST_RESET_SUBJECTS": "1",
            "FORUM_INDEX_UI_TEST_BOOKMARKS": try json([bookmark]),
            "FORUM_INDEX_UI_TEST_TOPIC": try json(topic),
            "FORUM_INDEX_UI_TEST_RESUME_JSON": try json(["https://example.com/t/123.json": failsResume ? "{}" : try json(index)]),
            "FORUM_INDEX_UI_TEST_MARKDOWN_PAGES": try json(pages),
            "FORUM_INDEX_UI_TEST_MARKDOWN": pages["\(url).md?page=1"]!,
            "FORUM_INDEX_UI_TEST_HTML": "<html><body>Long topic</body></html>"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Show bookmarks"].waitForExistence(timeout: 15))
        return app
    }
}
