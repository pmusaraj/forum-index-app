import Foundation

/// Reads reply activity directly from the bookmarked Discourse topic.
public struct BookmarkReplyClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func endpoint(for url: URL) -> URL? {
        guard WebNavigationPolicy.allows(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let parts = components.path.split(separator: "/")
        guard let topicIndex = parts.firstIndex(of: "t") else { return nil }
        let remaining = parts.dropFirst(topicIndex + 1)
        guard let id = remaining.first(where: { Int($0) != nil }) else { return nil }
        let prefix = parts.prefix(topicIndex).joined(separator: "/")
        components.path = (prefix.isEmpty ? "" : "/" + prefix) + "/t/\(id).json"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    public func latestReply(for url: URL) async throws -> Date? {
        guard let endpoint = Self.endpoint(for: url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode), WebNavigationPolicy.allows(response.url) else {
            throw URLError(.badServerResponse)
        }
        let activity = try JSONDecoder().decode(Activity.self, from: data)
        guard let value = activity.last_posted_at else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else { throw URLError(.cannotParseResponse) }
        return date
    }

    private struct Activity: Decodable {
        let last_posted_at: String?
    }
}
