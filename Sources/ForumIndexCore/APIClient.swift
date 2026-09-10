import Foundation

let signalLabelMaxUnicodeScalars = 100

func isValidSignalLabel(_ value: String) -> Bool {
    !value.isEmpty && value.unicodeScalars.count <= signalLabelMaxUnicodeScalars
}

public protocol APIClientProtocol: Sendable {
    func fetchTaxonomy() async throws -> NavigationEnvelope
    func fetchMainTopics(page: Int) async throws -> TopicFeedEnvelope
    func fetchParentTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope
    func fetchChildTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope
}

public protocol SignalAPIClientProtocol: Sendable {
    func enrollForSignals(inviteCode: String) async throws -> String
    func createInstallation(displayName: String, deviceName: String, deviceCheckToken: String?) async throws -> SignalEnrollment
    func fetchInstallation(bearerToken: String) async throws -> SignalInstallation
    func updateInstallation(deviceName: String, bearerToken: String) async throws -> SignalInstallation
    func setSignal(topicID: Int, value: Int, bearerToken: String) async throws
    func reportAction(topicID: Int, action: String, active: Bool, bearerToken: String) async throws
    func submitForum(url: String, bearerToken: String) async throws
    func revokeInstallation(bearerToken: String) async throws
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
    case invalidInviteCode
    case invalidSignalValue
    case invalidTopicID
    case invalidAction
    case invalidBearerToken
    case invalidResponse
    case httpStatus(Int)
    case transport(String)
    case decoding(String)
}

public final class URLSessionForumIndexAPIClient: APIClientProtocol, SignalAPIClientProtocol, Sendable {
    public static let productionBaseURL = URL(string: "https://do3.musaraj.com")!
    private static let feedPageSize = 30

    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let bearerToken: @Sendable () -> String?

    public init(
        session: URLSession = .shared,
        baseURL: URL = URLSessionForumIndexAPIClient.productionBaseURL,
        decoder: JSONDecoder = JSONDecoder(),
        bearerToken: @escaping @Sendable () -> String? = { nil }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.decoder = decoder
        self.bearerToken = bearerToken
    }

    public func fetchTaxonomy() async throws -> NavigationEnvelope {
        try await request(path: "/api/v2/subjects", queryItems: [
            URLQueryItem(name: "window", value: "5d")
        ])
    }

    public func fetchMainTopics(page: Int) async throws -> TopicFeedEnvelope {
        let token = bearerToken()
        do {
            return try await mainFeed(feed: "for_you", page: page, bearerToken: token)
        } catch ForumIndexAPIError.httpStatus(let status) where [400, 401, 403].contains(status) {
            return try await mainFeed(feed: "main", page: page)
        }
    }

    public func fetchParentTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope {
        try await topicFeed(pathPrefix: "/api/v2/subjects", slug: slug, page: page)
    }

    public func fetchChildTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope {
        try await topicFeed(pathPrefix: "/api/v2/subjects", slug: slug, page: page)
    }

    public func enrollForSignals(inviteCode: String) async throws -> String {
        guard !inviteCode.isEmpty else { throw ForumIndexAPIError.invalidInviteCode }
        let body = try JSONEncoder().encode(SignalEnrollmentRequest(inviteCode: inviteCode))
        let data = try await perform(path: "/api/v2/signal-enrollment", method: "POST", body: body)
        do {
            let token = try decoder.decode(SignalEnrollmentResponse.self, from: data).token
            guard !token.isEmpty else { throw ForumIndexAPIError.invalidResponse }
            return token
        } catch let error as ForumIndexAPIError {
            throw error
        } catch {
            throw ForumIndexAPIError.decoding(String(describing: error))
        }
    }

    public func createInstallation(
        displayName: String,
        deviceName: String,
        deviceCheckToken: String?
    ) async throws -> SignalEnrollment {
        guard isValidSignalLabel(displayName), isValidSignalLabel(deviceName) else {
            throw ForumIndexAPIError.invalidResponse
        }
        let body = try JSONEncoder().encode(InstallationRequest(
            displayName: displayName,
            deviceName: deviceName,
            deviceCheckToken: deviceCheckToken
        ))
        let data = try await perform(path: "/api/v2/installations", method: "POST", body: body)
        let enrollment = try decode(SignalEnrollment.self, from: data)
        guard !enrollment.token.isEmpty else { throw ForumIndexAPIError.invalidResponse }
        return enrollment
    }

    public func fetchInstallation(bearerToken: String) async throws -> SignalInstallation {
        try validateBearerToken(bearerToken)
        let data = try await perform(
            path: "/api/v2/installation",
            method: "GET",
            bearerToken: bearerToken
        )
        return try decode(InstallationResponse.self, from: data).installation
    }

    public func updateInstallation(deviceName: String, bearerToken: String) async throws -> SignalInstallation {
        guard isValidSignalLabel(deviceName) else { throw ForumIndexAPIError.invalidResponse }
        try validateBearerToken(bearerToken)
        let body = try JSONEncoder().encode(DeviceNameRequest(deviceName: deviceName))
        let data = try await perform(
            path: "/api/v2/installation",
            method: "PATCH",
            body: body,
            bearerToken: bearerToken
        )
        return try decode(InstallationResponse.self, from: data).installation
    }

    public func setSignal(topicID: Int, value: Int, bearerToken: String) async throws {
        guard topicID > 0, [-1, 0, 1].contains(value) else { throw ForumIndexAPIError.invalidSignalValue }
        try validateBearerToken(bearerToken)
        let body = try JSONEncoder().encode(SignalRequest(value: value))
        _ = try await perform(
            path: "/api/v2/topics/\(topicID)/signal",
            method: "PUT",
            body: body,
            bearerToken: bearerToken
        )
    }

    public func reportAction(topicID: Int, action: String, active: Bool, bearerToken: String) async throws {
        guard topicID > 0 else { throw ForumIndexAPIError.invalidTopicID }
        guard ["starred", "read", "low_quality", "inappropriate", "wrong_subject"].contains(action) else {
            throw ForumIndexAPIError.invalidAction
        }
        try validateBearerToken(bearerToken)
        let body = try JSONEncoder().encode(ActionRequest(kind: action, active: active))
        _ = try await perform(
            path: "/api/v2/topics/\(topicID)/action",
            method: "PUT",
            body: body,
            bearerToken: bearerToken
        )
    }

    public func submitForum(url: String, bearerToken: String) async throws {
        guard url.utf8.count <= 1_000 else { throw ForumIndexAPIError.invalidURL }
        try validateBearerToken(bearerToken)
        let body = try JSONEncoder().encode(ForumSubmissionRequest(url: url))
        _ = try await perform(
            path: "/api/v2/forum-submission",
            method: "POST",
            body: body,
            bearerToken: bearerToken,
            invalidBearerStatuses: [401]
        )
    }

    public func revokeInstallation(bearerToken: String) async throws {
        try validateBearerToken(bearerToken)
        _ = try await perform(
            path: "/api/v2/installation",
            method: "DELETE",
            bearerToken: bearerToken
        )
    }

    private func mainFeed(
        feed: String,
        page: Int,
        bearerToken: String? = nil
    ) async throws -> TopicFeedEnvelope {
        try await request(path: "/api/v2/topics", queryItems: [
            URLQueryItem(name: "feed", value: feed),
            URLQueryItem(name: "limit", value: "\(Self.feedPageSize)"),
            URLQueryItem(name: "page", value: "\(page)")
        ], bearerToken: bearerToken)
    }

    private func topicFeed(pathPrefix: String, slug: String, page: Int) async throws -> TopicFeedEnvelope {
        guard let encodedSlug = Self.encodedPathSegment(slug) else {
            throw ForumIndexAPIError.invalidSlug
        }
        return try await request(path: "\(pathPrefix)/\(encodedSlug)/topics", queryItems: [
            URLQueryItem(name: "feed", value: "trending"),
            URLQueryItem(name: "limit", value: "\(Self.feedPageSize)"),
            URLQueryItem(name: "page", value: "\(page)")
        ])
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        bearerToken: String? = nil
    ) async throws -> Response {
        try Task.checkCancellation()
        let url = try makeURL(path: path, queryItems: queryItems)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let data = try await responseData(for: urlRequest)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch let error as ForumIndexAPIError {
            throw error
        } catch {
            throw ForumIndexAPIError.decoding(String(describing: error))
        }
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw ForumIndexAPIError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw ForumIndexAPIError.httpStatus(response.statusCode) }
            return data
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

    private func perform(
        path: String,
        method: String,
        body: Data? = nil,
        bearerToken: String? = nil,
        invalidBearerStatuses: Set<Int> = [401, 403]
    ) async throws -> Data {
        try Task.checkCancellation()
        let url = try makeURL(path: path, queryItems: [], includesLanguage: false)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken {
            urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            return try await responseData(for: urlRequest)
        } catch ForumIndexAPIError.httpStatus(let status)
            where bearerToken != nil && invalidBearerStatuses.contains(status) {
            throw ForumIndexAPIError.invalidBearerToken
        }
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ForumIndexAPIError.decoding(String(describing: error))
        }
    }

    private func validateBearerToken(_ token: String) throws {
        guard !token.isEmpty,
              !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ForumIndexAPIError.invalidBearerToken
        }
    }

    private func makeURL(
        path: String,
        queryItems: [URLQueryItem],
        includesLanguage: Bool = true
    ) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
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
        let finalQueryItems = queryItems + (includesLanguage ? [URLQueryItem(name: "language", value: "en")] : [])
        components.queryItems = finalQueryItems.isEmpty ? nil : finalQueryItems
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

private struct SignalEnrollmentRequest: Encodable {
    let inviteCode: String
    enum CodingKeys: String, CodingKey { case inviteCode = "invite_code" }
}

private struct SignalEnrollmentResponse: Decodable { let token: String }
private struct SignalRequest: Encodable { let value: Int }
private struct ActionRequest: Encodable { let kind: String; let active: Bool }
private struct ForumSubmissionRequest: Encodable { let url: String }
private struct InstallationResponse: Decodable { let installation: SignalInstallation }
private struct DeviceNameRequest: Encodable {
    let deviceName: String
    enum CodingKeys: String, CodingKey { case deviceName = "device_name" }
}

private struct InstallationRequest: Encodable {
    let displayName: String
    let deviceName: String
    let deviceCheckToken: String?
    let deviceCheckEnvironment: String?

    init(displayName: String, deviceName: String, deviceCheckToken: String?) {
        self.displayName = displayName
        self.deviceName = deviceName
        self.deviceCheckToken = deviceCheckToken
#if DEBUG
        deviceCheckEnvironment = deviceCheckToken == nil ? nil : "development"
#else
        deviceCheckEnvironment = deviceCheckToken == nil ? nil : "production"
#endif
    }

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case deviceName = "device_name"
        case deviceCheckToken = "devicecheck_token"
        case deviceCheckEnvironment = "devicecheck_environment"
    }
}

public struct SignalEnrollment: Decodable, Equatable, Sendable {
    public let token: String
    public let installation: SignalInstallation

    public init(token: String, installation: SignalInstallation) {
        self.token = token
        self.installation = installation
    }
}

public struct SignalInstallation: Codable, Equatable, Sendable {
    public let publicID: String
    public let displayName: String
    public let deviceName: String
    public let deviceVerified: Bool
    public let trusted: Bool

    public init(publicID: String, displayName: String, deviceName: String, deviceVerified: Bool, trusted: Bool) {
        self.publicID = publicID
        self.displayName = displayName
        self.deviceName = deviceName
        self.deviceVerified = deviceVerified
        self.trusted = trusted
    }

    enum CodingKeys: String, CodingKey {
        case publicID = "public_id"
        case displayName = "display_name"
        case deviceName = "device_name"
        case deviceVerified = "device_verified"
        case trusted
    }
}
