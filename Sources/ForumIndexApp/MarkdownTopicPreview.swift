import ForumIndexCore
import SwiftUI

struct MarkdownTopicPreview: View {
    let topic: Topic
    let url: URL
    @Bindable var preloader: WebPagePreloader
    @State private var reader: MarkdownTopicReader?
    @State private var usesWebView = false
    @State private var markdownError: String?
    @State private var loadAttempt = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            TopicForumHeader(forum: topic.forum, isFullPageReady: preloader.isReady,
                             usesWebView: usesWebView, toggleView: toggleView)
            ZStack {
                Group {
                    if let reader {
                        TopicArticleView(topic: topic, reader: reader, url: url, isActive: !usesWebView)
                            .environment(\.openURL, OpenURLAction { destination in
                                guard WebNavigationPolicy.allows(destination) else { return .discarded }
                                openURL(destination)
                                return .handled
                            })
                    } else if let markdownError {
                        ContentUnavailableView {
                            Label("Couldn’t load the preview", systemImage: "exclamationmark.circle")
                        } description: {
                            Text(markdownError)
                        } actions: {
                            Button("Retry") { loadAttempt += 1 }
                        }
                    } else {
                        ProgressView("Loading topic…")
                            .accessibilityIdentifier("topic-loading")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(usesWebView ? 0 : 1)
                .allowsHitTesting(!usesWebView)
                .accessibilityHidden(usesWebView)

                if usesWebView {
                    fullPage
                }
            }
        }
        .background(Color("BrandBackground"))
        .task(id: loadAttempt) { await load() }
    }

    private var fullPage: some View {
        ZStack {
            PreloadedWebView(webView: preloader.webView)
                .accessibilityIdentifier("topic-html-preview")
                .opacity(preloader.isReady ? 1 : 0)
                .allowsHitTesting(preloader.isReady)
                .accessibilityHidden(!preloader.isReady)
            if !preloader.isReady {
                if preloader.loadError != nil {
                    ContentUnavailableView {
                        Label("Couldn’t load this topic", systemImage: "exclamationmark.circle")
                    } actions: {
                        Button("Retry") { preloader.retry() }
                    }
                } else {
                    ProgressView("Loading topic…")
                }
            }
        }
    }

    private func toggleView() {
        if usesWebView {
            usesWebView = false
        } else {
            showFullTopic()
        }
    }

    private func showFullTopic() {
        usesWebView = true
        preloader.preload(url)
        if preloader.loadError != nil { preloader.retry() }
    }

    private static func fetchPage(_ url: URL) async throws -> String {
#if DEBUG
        if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1",
           let json = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_MARKDOWN_PAGES"],
           let pages = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)),
           let markdown = pages[url.absoluteString] {
            return markdown
        }
#endif
        return try await TopicMarkdownClient().fetch(url: url)
    }

    private func load() async {
        markdownError = nil
        do {
            let markdown: String
#if DEBUG
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1",
               let fixture = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_MARKDOWN"] {
                markdown = fixture
            } else {
                markdown = try await TopicMarkdownClient().fetch(url: url)
            }
#else
            markdown = try await TopicMarkdownClient().fetch(url: url)
#endif
            try Task.checkCancellation()
            reader = MarkdownTopicReader(url: url, markdown: markdown, fetch: Self.fetchPage)
            preloader.preload(url, inBackground: true)
        } catch {
            // Dismissing a preview must not start a background web navigation.
            guard !Task.isCancelled else { return }
            markdownError = error.localizedDescription
            showFullTopic()
        }
    }
}
