import Foundation

public protocol APIClientProtocol: Sendable {
    func fetchTaxonomy() async throws -> NavigationEnvelope
    func fetchMainTopics(page: Int) async throws -> TopicFeedEnvelope
    func fetchParentTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope
    func fetchChildTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope
}

public extension APIClientProtocol {
    func fetchMainTopics() async throws -> TopicFeedEnvelope { try await fetchMainTopics(page: 1) }
    func fetchParentTopics(slug: String) async throws -> TopicFeedEnvelope { try await fetchParentTopics(slug: slug, page: 1) }
    func fetchChildTopics(slug: String) async throws -> TopicFeedEnvelope { try await fetchChildTopics(slug: slug, page: 1) }
}

public enum ForumIndexAPIError: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidSlug
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case transport(String)
    case decoding(String)
}

public final class URLSessionForumIndexAPIClient: APIClientProtocol, Sendable {
    public static let productionBaseURL = URL(string: "https://do3.musaraj.com")!
    private static let subjectPageSize = 30

    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder

    public init(
        session: URLSession = .shared,
        baseURL: URL = URLSessionForumIndexAPIClient.productionBaseURL,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.session = session
        self.baseURL = baseURL
        self.decoder = decoder
    }

    public func fetchTaxonomy() async throws -> NavigationEnvelope {
        try await request(path: "/api/v2/subjects", queryItems: [
            URLQueryItem(name: "window", value: "5d")
        ])
    }

    public func fetchMainTopics(page: Int) async throws -> TopicFeedEnvelope {
        try await request(path: "/api/v2/topics", queryItems: [
            URLQueryItem(name: "feed", value: "main"),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "page", value: "\(page)")
        ])
    }

    public func fetchParentTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope {
        try await topicFeed(pathPrefix: "/api/v2/subjects", slug: slug, page: page)
    }

    public func fetchChildTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope {
        try await topicFeed(pathPrefix: "/api/v2/subjects", slug: slug, page: page)
    }

    private func topicFeed(pathPrefix: String, slug: String, page: Int) async throws -> TopicFeedEnvelope {
        guard let encodedSlug = Self.encodedPathSegment(slug) else {
            throw ForumIndexAPIError.invalidSlug
        }
        return try await request(path: "\(pathPrefix)/\(encodedSlug)/topics", queryItems: [
            URLQueryItem(name: "feed", value: "trending"),
            URLQueryItem(name: "limit", value: "\(Self.subjectPageSize)"),
            URLQueryItem(name: "page", value: "\(page)")
        ])
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        try Task.checkCancellation()
        let url = try makeURL(path: path, queryItems: queryItems)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: urlRequest)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else {
                throw ForumIndexAPIError.invalidResponse
            }
            guard (200..<300).contains(response.statusCode) else {
                throw ForumIndexAPIError.httpStatus(response.statusCode)
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch let error as ForumIndexAPIError {
                throw error
            } catch {
                throw ForumIndexAPIError.decoding(String(describing: error))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ForumIndexAPIError {
            throw error
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch {
            throw ForumIndexAPIError.transport(String(describing: error))
        }
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw ForumIndexAPIError.invalidBaseURL
        }

        components.percentEncodedPath = Self.joinedPath(
            basePath: components.percentEncodedPath,
            apiPath: path
        )
        components.queryItems = queryItems + [URLQueryItem(name: "language", value: "en")]
        guard let url = components.url else { throw ForumIndexAPIError.invalidURL }
        return url
    }

    private static func joinedPath(basePath: String, apiPath: String) -> String {
        var basePath = basePath
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        return basePath + apiPath
    }

    private static func encodedPathSegment(_ slug: String) -> String? {
        guard !slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              slug != ".", slug != "..",
              !slug.contains("/"), !slug.contains("\\"), !slug.contains("%"),
              !slug.contains("?"), !slug.contains("#") else { return nil }

        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~ ")
        guard slug.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        var encodeAllowed = CharacterSet.alphanumerics
        encodeAllowed.insert(charactersIn: "-._~")
        return slug.addingPercentEncoding(withAllowedCharacters: encodeAllowed)
    }
}
