import ForumIndexCore
import SwiftUI

struct MarkdownTopicPreview: View {
    let topic: Topic
    let url: URL
    @Bindable var preloader: WebPagePreloader
    var safeAreaInsets = EdgeInsets()
    var onPageChange: (URL, String) -> Void = { _, _ in }
    @State private var pages: [MarkdownPreviewPage] = []
    @State private var usesWebView = false
    @State private var loadID = UUID()
    @Environment(\.openURL) private var openURL

    private var currentURL: URL { pages.last?.url ?? url }
    private var currentTitle: String { title(for: pages.last) }
    private var backAction: (() -> Void)? {
        guard pages.count > 1 else { return nil }
        return { goBack() }
    }

    var body: some View {
        VStack(spacing: 0) {
            TopicForumHeader(forum: topic.forum, isFullPageReady: preloader.isReady,
                             usesWebView: usesWebView, toggleView: toggleView,
                             goBack: backAction, safeAreaInsets: safeAreaInsets)
            ZStack {
                // Keep earlier articles mounted so Back restores their reader and scroll position.
                ForEach(pages) { page in
                    if let reader = page.reader {
                        TopicArticleView(
                            title: title(for: page),
                            publishedAt: page.url == url ? topic.publishedAt : nil,
                            replyCount: page.url == url ? topic.replyCount : nil,
                            externalSignals: page.url == url ? topic.externalSignals : [],
                            reader: reader, url: page.url,
                            safeAreaInsets: safeAreaInsets,
                            isActive: page.id == pages.last?.id && !usesWebView
                        )
                        .environment(\.openURL, OpenURLAction(handler: openMarkdownLink))
                        .opacity(page.id == pages.last?.id && !usesWebView ? 1 : 0)
                        .allowsHitTesting(page.id == pages.last?.id && !usesWebView)
                        .accessibilityHidden(page.id != pages.last?.id || usesWebView)
                    }
                }
                if pages.last?.reader == nil && !usesWebView {
                    Group {
                        if let error = pages.last?.error {
                            ContentUnavailableView {
                                Label("Couldn’t load the preview", systemImage: "exclamationmark.circle")
                            } description: {
                                Text(error)
                            } actions: {
                                Button("Retry") { loadID = UUID() }
                                Button("View full page", action: showFullTopic)
                            }
                        } else {
                            ProgressView("Loading topic…")
                                .accessibilityIdentifier("topic-loading")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if usesWebView {
                    fullPage
                }
            }
        }
        .background(Color("BrandBackground"), ignoresSafeAreaEdges: [])
        .task(id: loadID) { await load() }
        .onChange(of: currentURL) { notifyPageChange() }
        .onChange(of: currentTitle) { notifyPageChange() }
    }

    private var fullPage: some View {
        ZStack {
            PreloadedWebView(webView: preloader.webView, contentInsets: EdgeInsets(
                top: 0, leading: safeAreaInsets.leading, bottom: 0, trailing: safeAreaInsets.trailing
            ))
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
        showPage(currentURL)
    }

    private func openMarkdownLink(_ destination: URL) -> OpenURLAction.Result {
        guard let destination = WebNavigationPolicy.acceptedURL(
            URL(string: destination.relativeString, relativeTo: currentURL)?.absoluteURL
        ) else { return .discarded }
        if WebNavigationPolicy.externalURL(destination, relativeTo: currentURL) != nil {
            openURL(destination)
        } else {
            guard destination != currentURL else { return .handled }
            pages.append(MarkdownPreviewPage(url: destination))
            usesWebView = false
            loadID = UUID()
        }
        return .handled
    }

    private func showPage(_ destination: URL) {
        usesWebView = true
        preloader.preload(destination)
        if preloader.loadError != nil { preloader.retry() }
    }

    private func goBack() {
        guard pages.count > 1 else { return }
        pages.removeLast()
        usesWebView = false
        loadID = UUID()
    }

    private func title(for page: MarkdownPreviewPage?) -> String {
        guard let page, page.url != url else { return topic.title }
        return page.reader?.title ?? "Linked page"
    }

    private func notifyPageChange() {
        onPageChange(currentURL, currentTitle)
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
        if pages.isEmpty { pages.append(MarkdownPreviewPage(url: url)) }
        guard let page = pages.last else { return }
        if page.reader != nil {
            preloader.preload(page.url, inBackground: !usesWebView)
            return
        }
        pages[pages.count - 1].error = nil
        do {
            let markdown: String
#if DEBUG
            if page.url == url,
               ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1",
               let fixture = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_MARKDOWN"] {
                markdown = fixture
            } else {
                markdown = try await Self.fetchPage(page.url)
            }
#else
            markdown = try await Self.fetchPage(page.url)
#endif
            try Task.checkCancellation()
            guard pages.last?.id == page.id else { return }
            pages[pages.count - 1].reader = MarkdownTopicReader(url: page.url, markdown: markdown, fetch: Self.fetchPage)
            preloader.preload(page.url, inBackground: !usesWebView)
        } catch {
            // Dismissing a preview must not start a background web navigation.
            guard !Task.isCancelled, pages.last?.id == page.id else { return }
            pages[pages.count - 1].error = error.localizedDescription
            if page.url == url { showFullTopic() }
        }
    }
}
