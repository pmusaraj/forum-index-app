import XCTest

final class MarkdownPreviewUITests: XCTestCase {
    @MainActor
    func testRecentMetaTopicWithPublishedSummary() throws {
        // Public topic and its unmodified Markdown captured from Meta on October 14, 2026.
        let bundle = Bundle(for: Self.self)
        let markdown = try XCTUnwrap(bundle.url(forResource: "MetaAISummary", withExtension: "md", subdirectory: "Fixtures"))
        let topicJSON = try XCTUnwrap(bundle.url(forResource: "MetaAISummary", withExtension: "json", subdirectory: "Fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_TOPIC"] = try String(contentsOf: topicJSON, encoding: .utf8)
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = try String(contentsOf: markdown, encoding: .utf8)
        app.launch()
        let topic = app.buttons["topic-1-414624"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        let toggle = app.buttons["topic-summary-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        capture(app, name: "Meta-summary-collapsed")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Hide AI summary")
        XCTAssertTrue(app.staticTexts["AI-generated summary"].exists)
        capture(app, name: "Meta-summary-expanded")
        toggle.tap()
        let preview = app.scrollViews["topic-markdown-preview"]
        let footer = app.staticTexts["You reached the end of topic: AI agents signing up for accounts in meta.discourse.org"]
        for _ in 0..<25 where !footer.isHittable { preview.swipeUp() }
        XCTAssertTrue(footer.isHittable)
        preview.swipeUp()
        XCTAssertTrue(app.staticTexts["7 replies · 5 participants"].exists)
        capture(app, name: "Meta-topic-footer")
    }

    @MainActor
    func testSummaryToggleAndCompletionFooter() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_TOPIC"] = #"{"id":123,"title":"AI summaries in topic Markdown","published_at":"2026-10-09T12:00:00Z","engagement":{"replies":1},"url":"https://meta.discourse.org/t/example/123","forum":{"id":1,"name":"Discourse Meta","slug":"meta","base_url":"https://meta.discourse.org","supports_markdown":true}}"#
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = """
        # AI summaries in topic Markdown

        **URL:** https://meta.discourse.org/t/example/123
        **Page:** 1

        ## AI-generated summary

        A **published overview** of the discussion.

        <div class="post-metadata">
        **Author:** [@alice](https://meta.discourse.org/u/alice)
        </div>

        Topics can now include an AI summary in their Markdown output.

        ---

        <div class="post-metadata">
        **Author:** [@bob](https://meta.discourse.org/u/bob)
        </div>

        The full discussion is still there for anyone who wants more context.
        """
        app.launch()
        let topic = app.buttons["topic-1-123"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        let toggle = app.buttons["topic-summary-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.label, "AI summary")
        let overview = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "published overview")).firstMatch
        XCTAssertFalse(overview.exists)
        capture(app, name: "Summary-collapsed")
        toggle.tap()
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Hide AI summary")
        capture(app, name: "Summary-expanded")
        toggle.tap()
        XCTAssertTrue(overview.waitForNonExistence(timeout: 5))
        let footer = app.staticTexts["You reached the end of topic: AI summaries in topic Markdown in meta.discourse.org"]
        let preview = app.scrollViews["topic-markdown-preview"]
        for _ in 0..<3 where !footer.isHittable { preview.swipeUp() }
        XCTAssertTrue(footer.isHittable)
        XCTAssertTrue(app.staticTexts["1 reply · 2 participants"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["topic-browser-footer"].firstMatch.exists)
        capture(app, name: "Topic-completion-footer")
    }

    @MainActor
    func testSelectingTextInJuliaTopic() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "JuliaAI", withExtension: "md", subdirectory: "Fixtures"
        ))
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_TOPIC"] = #"{"id":139973,"title":"How to start using AI?","url":"https://discourse.julialang.org/t/how-to-start-using-ai/139973","forum":{"id":1,"name":"Julia","slug":"julia","base_url":"https://discourse.julialang.org","supports_markdown":true}}"#
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = try String(contentsOf: fixture, encoding: .utf8)
        app.launch()
        let topic = app.buttons["topic-1-139973"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        let paragraph = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@", "I’m looking for guidance"
        )).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10))
        // Exercise the initial layout and starting a new selection after Copy.
        for _ in 0..<2 {
            paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
                .press(forDuration: 1.2)
            let copy = app.menuItems["Copy"].firstMatch
            XCTAssertTrue(copy.waitForExistence(timeout: 5))
            copy.tap()
            XCTAssertEqual(app.state, .runningForeground)
            paragraph.tap() // Clear the retained highlight before starting another selection.
        }
        XCTAssertTrue(app.scrollViews["topic-markdown-preview"].exists)
    }

    @MainActor
    func testExternalSignalsAppearInListAndAboveFirstPost() throws {
        let app = try launchExample(openTopic: false, externalSignals: true)
        let topic = app.buttons["topic-1-412871"].firstMatch
        XCTAssertTrue(topic.label.contains("Discussed on Hacker News"))
        XCTAssertTrue(topic.label.contains("Discussed on Lobsters"))
        capture(app, name: "External-signals-topic-list")
        topic.tap()
        let hn = app.descendants(matching: .any)["external-signal-hacker_news"].firstMatch
        let lobsters = app.descendants(matching: .any)["external-signal-lobsters"].firstMatch
        XCTAssertTrue(hn.waitForExistence(timeout: 10))
        XCTAssertTrue(lobsters.isHittable)
        XCTAssertGreaterThan(hn.frame.minY, app.staticTexts["topic-preview-title"].frame.maxY)
        capture(app, name: "External-signals-topic-detail")
        hn.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10))
    }

    @MainActor
    func testTitleElementFollowsScrollDirection() throws {
        let app = try launchExample()
        let preview = app.scrollViews["topic-markdown-preview"]
        let title = app.staticTexts["topic-preview-title"]
        let stickyTitle = app.staticTexts["topic-sticky-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertFalse(stickyTitle.exists)
        preview.swipeUp(velocity: .slow)
        preview.swipeUp(velocity: .slow)
        XCTAssertFalse(stickyTitle.exists)
        let lower = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let upper = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        lower.press(forDuration: 0.05, thenDragTo: upper)
        XCTAssertTrue(stickyTitle.waitForExistence(timeout: 3))
        XCTAssertEqual(stickyTitle.label, title.label)
        capture(app, name: "Topic-title-revealed")
        upper.press(forDuration: 0.05, thenDragTo: lower)
        XCTAssertTrue(stickyTitle.waitForNonExistence(timeout: 3))
        for _ in 0..<4 { preview.swipeDown(velocity: .slow) }
        XCTAssertTrue(title.isHittable)
        XCTAssertFalse(stickyTitle.exists)
    }

    @MainActor
    func testAboutOpensTopicInReader() throws {
        let app = try launchExample(openTopic: false)
        let row = app.buttons["topic-1-412871"].firstMatch
        row.press(forDuration: 1)
        app.buttons["topic-context-about"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["A community for Discourse discussions."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["topic-about-parent-link"].exists)
        capture(app, name: "Topic-about")
        app.buttons["topic-about-open-topic"].tap()
        XCTAssertTrue(app.staticTexts["topic-preview-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.sheets.count, 0)
        app.buttons["Dismiss topic"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAppearanceChoicePersistsAndCanReturnToAuto() throws {
        let app = try launchExample(openTopic: false)
        app.buttons["Contribution settings"].tap()
        let picker = app.segmentedControls["appearance-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["Auto"].isSelected)
        picker.buttons["Dark"].tap()
        XCTAssertTrue(picker.buttons["Dark"].isSelected)
        capture(app, name: "Settings-dark-override")
        app.terminate()
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_APPEARANCE"] = nil
        app.launch()
        XCTAssertTrue(app.buttons["Contribution settings"].waitForExistence(timeout: 10))
        app.buttons["Contribution settings"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["Dark"].isSelected)
        picker.buttons["Light"].tap()
        XCTAssertTrue(picker.buttons["Light"].isSelected)
        capture(app, name: "Settings-light-override")
        picker.buttons["Auto"].tap()
        XCTAssertTrue(picker.buttons["Auto"].isSelected)
        capture(app, name: "Settings-auto")
    }

    @MainActor
    func testSettingsAppearanceScreenshot() throws {
        let app = try launchExample(openTopic: false)
        app.buttons["Contribution settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture(app, name: "Appearance-settings")
    }

    /// Run in both simulator appearances to review native surfaces and presentation.
    @MainActor
    func testAppearanceScreenshots() throws {
        let app = try launchExample(openTopic: false)
        capture(app, name: "Appearance-topic-list")
        app.buttons["topic-1-412871"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["topic-preview-title"].waitForExistence(timeout: 10))
        capture(app, name: "Appearance-topic-reader")
        app.buttons["topic-header-forum-overview"].tap()
        XCTAssertTrue(app.buttons["forum-overview-forum-link"].waitForExistence(timeout: 5))
        capture(app, name: "Appearance-forum-overview")
    }

    @MainActor
    func testForumHeaderShowsOverviewBubble() throws {
        let app = try launchExample()
        let header = app.buttons["topic-header-forum-overview"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        header.tap()
        XCTAssertTrue(app.staticTexts["A community for Discourse discussions."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["forum-overview-forum-link"].exists)
        XCTAssertTrue(app.buttons["forum-overview-organization-link"].exists)
        XCTAssertTrue(app.staticTexts["discourse.org"].exists)
        capture(app, name: "Forum-overview-bubble")
    }

    /// Snapshots of four real GET /api/v2/forums/:id responses captured on 2026-09-24.
    @MainActor
    func testFourSiteOverviewSnapshots() throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "ForumOverviews", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        for site in cases {
            let topic = try XCTUnwrap(site["topic"] as? [String: Any])
            let detail = try XCTUnwrap(site["detail"] as? [String: Any])
            let forum = try XCTUnwrap(detail["forum"] as? [String: Any])
            let forumID = try XCTUnwrap(forum["id"] as? Int)
            let topicID = try XCTUnwrap(topic["id"] as? Int)
            let app = XCUIApplication()
            app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
            app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
            app.launchEnvironment["FORUM_INDEX_UI_TEST_TOPIC"] = String(decoding: try JSONSerialization.data(withJSONObject: topic), as: UTF8.self)
            app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = try XCTUnwrap(site["markdown"] as? String)
            app.launchEnvironment["FORUM_INDEX_UI_TEST_FORUM_DETAIL"] = String(decoding: try JSONSerialization.data(withJSONObject: detail), as: UTF8.self)
            app.launch()
            let row = app.buttons["topic-\(forumID)-\(topicID)"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            row.tap()
            let header = app.buttons["topic-header-forum-overview"]
            XCTAssertTrue(header.waitForExistence(timeout: 10))
            header.tap()
            let forumLink = app.buttons["forum-overview-forum-link"]
            XCTAssertTrue(forumLink.waitForExistence(timeout: 5))
            XCTAssertEqual(forumLink.label, "Open forum in browser")
            let description = try XCTUnwrap(forum["description"] as? String)
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", description)).firstMatch.exists)
            if let parent = forum["parent_site_url"] as? String {
                XCTAssertTrue(app.buttons["forum-overview-organization-link"].exists)
                XCTAssertTrue(app.staticTexts[try XCTUnwrap(URL(string: parent)?.host())].exists)
            } else {
                XCTAssertFalse(app.buttons["forum-overview-organization-link"].exists)
                XCTAssertFalse(app.staticTexts["Organization website unavailable."].exists)
            }
            capture(app, name: "Forum-overview-\(forumID)")
            app.terminate()
        }
    }

    @MainActor
    func testInternalMarkdownLinkOpensInCurrentScreen() throws {
        let bundle = Bundle(for: Self.self)
        let markdownURL = try XCTUnwrap(bundle.url(forResource: "OpenZitiShareConflict", withExtension: "md", subdirectory: "Fixtures"))
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_TOPIC"] = #"{"id":6112,"title":"Share conflict, can't delete or create public share","url":"https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112","forum":{"id":1,"name":"OpenZiti","slug":"openziti","base_url":"https://openziti.discourse.group","supports_markdown":true}}"#
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = try String(contentsOf: markdownURL, encoding: .utf8)
        app.launch()
        let topic = app.buttons["topic-1-6112"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        let preview = app.scrollViews["topic-markdown-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        let link = app.links.matching(NSPredicate(format: "label CONTAINS %@", "Stuck zrok2 account")).firstMatch
        for _ in 0..<5 {
            if link.exists && preview.frame.contains(link.frame) { break }
            preview.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(link.exists)
        XCTAssertTrue(preview.frame.contains(link.frame))
        let linkY = link.frame.minY
        // Textual exposes inline links without an XCTest hit point. Tap the visible text.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: link.frame.midX, dy: link.frame.midY)).tap()
        let linkedTitle = app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH %@", "topic-preview-title", "Stuck zrok2 account"
        )).firstMatch
        XCTAssertTrue(linkedTitle.waitForExistence(timeout: 20))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["@smilindave26"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "**Showing post:**")).firstMatch.exists)
        let toggle = app.buttons["topic-header-full-html"]
        XCTAssertEqual(toggle.label, "View full topic")
        capture(app, name: "OpenZiti-linked-markdown")

        toggle.tap()
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 30))
        // A post deep link scrolls the heading offscreen; the web document still exposes its title.
        let webTitle = webView.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Stuck zrok2 account")).firstMatch
        XCTAssertTrue(webTitle.waitForExistence(timeout: 20))
        XCTAssertEqual(toggle.label, "Show Markdown preview")
        capture(app, name: "OpenZiti-linked-browser")
        toggle.tap()
        XCTAssertTrue(linkedTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)

        app.buttons["topic-header-back"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["topic-preview-title"].label, "Share conflict, can't delete or create public share")
        XCTAssertEqual(link.frame.minY, linkY, accuracy: 2)
        XCTAssertFalse(app.buttons["topic-header-back"].exists)
        XCTAssertEqual(toggle.label, "View full topic")
    }

    @MainActor
    func testLegacyForumDomainRedirectLoadsTopic() {
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_TOPIC"] = #"{"id":5823105,"title":"The listening e","url":"https://community.security.eufy.com/t/the-listening-e/5823105","engagement":{"replies":1},"forum":{"id":1,"name":"Eufy","slug":"eufy","base_url":"https://community.security.eufy.com","supports_markdown":false}}"#
        app.launch()
        let topic = app.buttons["topic-1-5823105"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        topic.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["Couldn’t load this topic"].exists)
    }

    @MainActor
    func testMetaDiscoursePostLayoutAndStickyHeader() throws {
        let app = try launchExample()
        let title = app.staticTexts["topic-preview-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Require LLM-generated themes & plugins to be tagged as such")
        XCTAssertTrue(app.staticTexts["@darkpixlz"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["32 replies"].exists)
        XCTAssertFalse(app.buttons["Open in browser"].exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "<div class=")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "URL:")).firstMatch.exists)
        let forumName = app.staticTexts["Discourse Meta"].firstMatch
        XCTAssertTrue(forumName.exists)
        let headerY = forumName.frame.minY
        capture(app, name: "Meta-topic-top")

        app.scrollViews["topic-markdown-preview"].swipeUp(velocity: .slow)
        XCTAssertEqual(forumName.frame.minY, headerY, accuracy: 1)
        XCTAssertTrue(forumName.isHittable)
        capture(app, name: "Meta-topic-posts-sticky-header")
    }

    @MainActor
    func testRepliesAutomaticallyLoadNearTheEnd() throws {
        let app = try launchExample(paginated: true)
        XCTAssertTrue(app.staticTexts["topic-preview-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["topic-full-html"].exists)
        let author = app.staticTexts["@page-two-author"]
        XCTAssertFalse(author.exists)
        for _ in 0..<12 {
            if author.exists { break }
            app.scrollViews["topic-markdown-preview"].swipeUp()
        }
        XCTAssertTrue(author.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "topic-preview-title").count, 1)
        XCTAssertTrue(app.buttons["topic-header-full-html"].exists)
        XCTAssertFalse(app.buttons["topic-full-html"].exists)
    }

    @MainActor
    func testHeaderOpensBackgroundLoadedPage() throws {
        let app = try launchExample()
        let button = app.buttons["topic-header-full-html"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ready"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 25), .completed)
        XCTAssertTrue(app.scrollViews["topic-markdown-preview"].exists)
        app.scrollViews["topic-markdown-preview"].swipeUp(velocity: .slow)
        let author = app.staticTexts["@RGJ"].firstMatch
        XCTAssertTrue(author.isHittable)
        let authorY = author.frame.minY
        let headerY = button.frame.minY
        button.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews["topic-markdown-preview"].isHittable)
        XCTAssertTrue(button.isHittable)
        XCTAssertEqual(button.label, "Show Markdown preview")
        XCTAssertEqual(button.frame.minY, headerY, accuracy: 1)
        button.tap()
        XCTAssertTrue(app.scrollViews["topic-markdown-preview"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertEqual(author.frame.minY, authorY, accuracy: 2)
        XCTAssertEqual(button.label, "View full topic")
        button.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchExample(paginated: Bool = false, openTopic: Bool = true, externalSignals: Bool = false) throws -> XCUIApplication {
        let bundle = Bundle(for: Self.self)
        let topicURL = try XCTUnwrap(bundle.url(forResource: "MetaDiscourseTopic", withExtension: "json", subdirectory: "Fixtures"))
        let markdownURL = try XCTUnwrap(bundle.url(forResource: "MetaDiscourseTopic", withExtension: "md", subdirectory: "Fixtures"))
        var markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        var nextPages: [String: String] = [:]
        if paginated, let separator = markdown.range(of: "\n---\n") {
            markdown = String(markdown[..<separator.lowerBound])
            markdown += String(repeating: "\n\nMore first-page discussion to read before the next page. This paragraph keeps the initial page taller than two viewports so scrolling is required to load further replies.", count: 10)
            let nextURL = "https://meta.discourse.org/t/require-llm-generated-themes-plugins-to-be-tagged-as-such/412871.md?page=2"
            markdown += "\n\n[Next page](\(nextURL))"
            nextPages[nextURL] = """
            # Example topic

            **URL:** https://meta.discourse.org/t/require-llm-generated-themes-plugins-to-be-tagged-as-such/412871
            **Page:** 2

            <div class="post-metadata">
            ### Author: [@page-two-author](https://meta.discourse.org/u/page-two-author)
            </div>

            A reply automatically loaded from page two.
            """
        }
        let app = XCUIApplication()
        app.launchEnvironment["FORUM_INDEX_UI_TESTING"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] = "1"
        var topicJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: topicURL)) as? [String: Any])
        if externalSignals {
            topicJSON["external_signals"] = [
                ["source": "hacker_news", "url": "https://news.ycombinator.com/item?id=1"],
                ["source": "lobsters", "url": "https://lobste.rs/s/example/discussion"]
            ]
        }
        app.launchEnvironment["FORUM_INDEX_UI_TEST_TOPIC"] = String(decoding: try JSONSerialization.data(withJSONObject: topicJSON), as: UTF8.self)
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN"] = markdown
        app.launchEnvironment["FORUM_INDEX_UI_TEST_FORUM_DETAIL"] = #"{"version":"v2","forum":{"id":1,"name":"Discourse Meta","slug":"meta","base_url":"https://meta.discourse.org","site_url":"https://meta.discourse.org","parent_site_url":"https://discourse.org","description":"A community for Discourse discussions."}}"#
        app.launchEnvironment["FORUM_INDEX_UI_TEST_RESET_APPEARANCE"] = "1"
        app.launchEnvironment["FORUM_INDEX_UI_TEST_MARKDOWN_PAGES"] = String(decoding: try JSONEncoder().encode(nextPages), as: UTF8.self)
        app.launch()
        let topic = app.buttons["topic-1-412871"].firstMatch
        XCTAssertTrue(topic.waitForExistence(timeout: 15))
        if openTopic { topic.tap() }
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
