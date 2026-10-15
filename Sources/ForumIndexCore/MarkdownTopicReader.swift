import Foundation
import Observation

@MainActor
@Observable
public final class MarkdownTopicReader {
    public let title: String?
    public let summary: String?
    public let startsTopic: Bool
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
        nextPageURL = TopicPagination.nextURL(document.nextPageURL, for: url, after: 1)
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
            posts.append(contentsOf: document.posts)
            reachedLastPage = !document.hasNextPage && !document.posts.isEmpty
            // Empty pages and backward/repeated links end pagination instead of looping.
            nextPageURL = document.posts.isEmpty ? nil
                : TopicPagination.nextURL(document.nextPageURL, for: topicURL, after: pageNumber)
        } catch {
            guard !Task.isCancelled else { return }
            loadMoreError = "Couldn’t load more replies."
        }
    }
}
