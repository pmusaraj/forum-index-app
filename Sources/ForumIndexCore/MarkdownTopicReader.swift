import Foundation
import Observation

@MainActor
@Observable
public final class MarkdownTopicReader {
    public let title: String?
    public private(set) var summary: String?
    public private(set) var startsTopic: Bool
    private var reachedLastPage: Bool

    public var hasCompleteTopic: Bool {
        startsTopic && reachedLastPage && !posts.isEmpty && !isLoadingMore && loadMoreError == nil
    }

    /// Only report totals when every post has an author and every page has loaded.
    public var participantCount: Int? {
        guard hasCompleteTopic, posts.allSatisfy({ $0.username != nil }) else { return nil }
        return Set(posts.compactMap { $0.username?.lowercased() }).count
    }

    public var replyCount: Int? {
        guard participantCount != nil else { return nil }
        return max(0, posts.count - 1)
    }

    public private(set) var posts: [MarkdownPost]
    public private(set) var nextPageURL: URL?
    public private(set) var previousPageURL: URL?
    public private(set) var isLoadingPrevious = false
    public private(set) var loadPreviousError: String?
    public var firstUnreadPostNumber: Int?
    public var initialPostID: Int?
    public var readThrough: Int = 0
    public var latestReplyAt: Date?
    public private(set) var isLoadingMore = false
    public private(set) var loadMoreError: String?

    private let topicURL: URL
    private let fetch: @Sendable (URL) async throws -> String
    private var loadedPages: Set<Int> = [1]

    public init(
        url: URL,
        markdown: String,
        fetch: @escaping @Sendable (URL) async throws -> String = { try await TopicMarkdownClient().fetch(url: $0) }
    ) {
        topicURL = url
        self.fetch = fetch
        let document = MarkdownTopicDocument(markdown: markdown, baseURL: url)
        title = document.title
        summary = document.summary
        startsTopic = document.startsTopic
        reachedLastPage = !document.hasNextPage
        posts = document.posts
        loadedPages = [document.pageNumber]
        nextPageURL = TopicPagination.nextURL(document.nextPageURL, for: url, after: document.pageNumber)
        previousPageURL = TopicPagination.previousURL(document.previousPageURL, for: url, before: document.pageNumber)
    }

    public func loadNextPage(retrying: Bool = false) async {
        guard let url = nextPageURL, !isLoadingMore,
              retrying || loadMoreError == nil,
              let pageNumber = TopicPagination.pageNumber(url), !loadedPages.contains(pageNumber) else { return }
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }
        do {
            let markdown = try await fetch(url)
            try Task.checkCancellation()
            let document = MarkdownTopicDocument(markdown: markdown, baseURL: url, postIDOffset: posts.count)
            loadedPages.insert(pageNumber)
            let existing = Set(posts.map(\.id))
            posts.append(contentsOf: document.posts.filter { !existing.contains($0.id) })
            reachedLastPage = !document.hasNextPage && !document.posts.isEmpty
            // Empty pages and backward/repeated links end pagination instead of looping.
            nextPageURL = document.posts.isEmpty ? nil
                : TopicPagination.nextURL(document.nextPageURL, for: topicURL, after: pageNumber)
        } catch {
            guard !Task.isCancelled else { return }
            loadMoreError = "Couldn’t load more replies."
        }
    }

    public func loadPreviousPage(retrying: Bool = false) async {
        guard let url = previousPageURL, !isLoadingPrevious,
              retrying || loadPreviousError == nil,
              let page = TopicPagination.pageNumber(url), !loadedPages.contains(page) else { return }
        isLoadingPrevious = true
        loadPreviousError = nil
        defer { isLoadingPrevious = false }
        do {
            let markdown = try await fetch(url)
            try Task.checkCancellation()
            let document = MarkdownTopicDocument(markdown: markdown, baseURL: url, postIDOffset: posts.count)
            let existing = Set(posts.map(\.id))
            let earlier = document.posts.filter { !existing.contains($0.id) }
            posts.insert(contentsOf: earlier, at: 0)
            loadedPages.insert(page)
            startsTopic = startsTopic || document.startsTopic
            if document.startsTopic { summary = document.summary }
            previousPageURL = document.posts.isEmpty ? nil
                : TopicPagination.previousURL(document.previousPageURL, for: topicURL, before: page)
        } catch {
            guard !Task.isCancelled else { return }
            loadPreviousError = "Couldn’t load earlier replies."
        }
    }
}
