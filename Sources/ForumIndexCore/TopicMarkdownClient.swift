import Foundation

/// Fetches the forum's negotiated Markdown representation, never the feed's HTML excerpt.
public struct TopicMarkdownClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    private static let retryGate = RetryGate()

    public func fetch(url: URL) async throws -> String {
        try await Self.retryGate.check(url)
        let request = try Self.request(for: url)
        let (data, response) = try await session.data(for: request)
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode),
           let value = response.value(forHTTPHeaderField: "Retry-After"),
           let deadline = Self.retryDate(value) {
            await Self.retryGate.record(url, until: deadline)
        }
        try Task.checkCancellation()
        return try Self.decode(data: data, response: response)
    }

    static func retryDate(_ value: String, now: Date = Date()) -> Date? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }

    /// Shared across initial loads and pagination, including newly created clients.
    private actor RetryGate {
        var deadlines: [String: Date] = [:]

        func check(_ url: URL) throws {
            let key = url.host?.lowercased() ?? url.absoluteString
            if let deadline = deadlines[key], deadline > Date() {
                throw URLError(.resourceUnavailable, userInfo: [
                    NSLocalizedDescriptionKey: "The reader is temporarily unavailable. Please try again after \(deadline.formatted())."
                ])
            }
            deadlines[key] = nil
        }

        func record(_ url: URL, until deadline: Date) {
            let key = url.host?.lowercased() ?? url.absoluteString
            deadlines[key] = max(deadlines[key] ?? .distantPast, deadline)
        }
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
