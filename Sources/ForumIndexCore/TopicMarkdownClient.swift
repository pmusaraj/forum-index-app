import Foundation

/// Fetches the forum's negotiated Markdown representation, never the feed's HTML excerpt.
public struct TopicMarkdownClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(url: URL) async throws -> String {
        let request = try Self.request(for: url)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        return try Self.decode(data: data, response: response)
    }

    static func request(for url: URL) throws -> URLRequest {
        guard WebNavigationPolicy.allows(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")
        return request
    }

    static func decode(data: Data, response: URLResponse) throws -> String {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              WebNavigationPolicy.allows(response.url),
              response.mimeType?.lowercased() == "text/markdown",
              let markdown = String(data: data, encoding: .utf8),
              !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw URLError(.badServerResponse)
        }
        return markdown
    }
}
