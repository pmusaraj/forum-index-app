import Foundation
import Observation

@MainActor
@Observable
public final class MarkdownTopicReader {
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
            // Empty pages and backward/repeated links end pagination instead of looping.
            nextPageURL = document.posts.isEmpty ? nil
                : TopicPagination.nextURL(document.nextPageURL, for: topicURL, after: pageNumber)
        } catch {
            guard !Task.isCancelled else { return }
            loadMoreError = "Couldn’t load more replies."
        }
    }
}
