import Foundation

/// Locates a Markdown page using the lightweight post-ID stream, without walking earlier pages.
public struct TopicResumeClient: Sendable {
    private let fetch: @Sendable (URL) async throws -> Data

    public init(fetch: @escaping @Sendable (URL) async throws -> Data = Self.fetchJSON) {
        self.fetch = fetch
    }

    public struct Target: Equatable, Sendable {
        public let pageURL: URL
        public let postNumber: Int?
        public let readThrough: Int
        public let latestReplyAt: Date?
    }

    public func target(for bookmark: Bookmark) async throws -> Target {
        guard let endpoint = BookmarkReplyClient.endpoint(for: bookmark.url) else { throw URLError(.unsupportedURL) }
        let topic = try JSONDecoder().decode(TopicIndex.self, from: await fetch(endpoint))
        let ids = topic.post_stream.stream
        guard !ids.isEmpty, topic.chunk_size > 0 else { throw URLError(.cannotParseResponse) }
        var cache = Dictionary(topic.post_stream.posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let baseline = bookmark.lastReadAt ?? bookmark.addedAt ?? .distantPast
        var low = 0
        var high = ids.count
        // Post numbers have gaps after deletion; never infer them from array offsets.
        while low < high {
            try Task.checkCancellation()
            let middle = (low + high) / 2
            let post = try await post(at: middle, ids: ids, endpoint: endpoint, cache: &cache)
            let isUnread = try bookmark.lastReadPostNumber.map { post.post_number > $0 }
                ?? (Self.date(post.created_at) > baseline)
            if isUnread { high = middle } else { low = middle + 1 }
        }
        let previous = low > 0 ? try await post(at: low - 1, ids: ids, endpoint: endpoint, cache: &cache).post_number : 0
        let number = low < ids.count ? try await post(at: low, ids: ids, endpoint: endpoint, cache: &cache).post_number : nil
        let page = number == nil ? 1 : low / topic.chunk_size + 1
        var components = URLComponents(url: bookmark.url, resolvingAgainstBaseURL: true)!
        // Canonical topic URL; bookmark links may include a post number.
        let parts = components.path.split(separator: "/")
        if let t = parts.firstIndex(of: "t"), let id = parts.dropFirst(t + 1).firstIndex(where: { Int($0) != nil }) {
            components.path = "/" + parts.prefix(through: id).joined(separator: "/") + ".md"
        }
        components.queryItems = [URLQueryItem(name: "page", value: String(page))]
        components.fragment = nil
        return Target(pageURL: components.url!, postNumber: number,
                      readThrough: max(previous, bookmark.lastReadPostNumber ?? 0),
                      latestReplyAt: try topic.last_posted_at.map(Self.date))
    }

    /// A converter page cannot be inferred from an upstream post number.
    public static func originalURL(for target: Target, topicURL: URL) -> URL {
        guard let number = target.postNumber,
              var components = URLComponents(url: topicURL, resolvingAgainstBaseURL: true) else { return topicURL }
        let parts = components.path.split(separator: "/")
        guard let t = parts.firstIndex(of: "t"),
              let id = parts.dropFirst(t + 1).firstIndex(where: { Int($0) != nil }) else { return topicURL }
        components.path = "/" + parts.prefix(through: id).joined(separator: "/") + "/\(number)"
        components.query = nil
        components.fragment = nil
        return components.url ?? topicURL
    }

    private func post(at index: Int, ids: [Int], endpoint: URL, cache: inout [Int: Post]) async throws -> Post {
        let id = ids[index]
        if let post = cache[id] { return post }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true)!
        components.path = endpoint.path.replacingOccurrences(of: ".json", with: "/posts.json")
        components.queryItems = [URLQueryItem(name: "post_ids[]", value: String(id))]
        let response = try JSONDecoder().decode(PostResponse.self, from: await fetch(components.url!))
        guard let post = response.post_stream.posts.first(where: { $0.id == id }) else {
            // The stream changed while locating the boundary. A retry gets a fresh snapshot.
            throw URLError(.resourceUnavailable)
        }
        cache[id] = post
        return post
    }

    public static func fetchJSON(_ url: URL) async throws -> Data {
        guard WebNavigationPolicy.allows(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              WebNavigationPolicy.allows(response.url) else { throw URLError(.badServerResponse) }
        return data
    }

    private static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) else {
            throw URLError(.cannotParseResponse)
        }
        return date
    }

    private struct TopicIndex: Decodable {
        let post_stream: Stream
        let chunk_size: Int
        let last_posted_at: String?
    }
    private struct Stream: Decodable {
        let stream: [Int]
        let posts: [Post]
    }
    private struct PostResponse: Decodable {
        let post_stream: Posts
    }
    private struct Posts: Decodable { let posts: [Post] }
    private struct Post: Decodable {
        let id: Int
        let post_number: Int
        let created_at: String
    }
}
