import Foundation

public protocol APIClientProtocol: Sendable {
    func fetchTaxonomy() async throws -> NavigationEnvelope
    func fetchMainTopics(page: Int) async throws -> TopicFeedEnvelope
    func fetchParentTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope
    func fetchChildTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope
}

public protocol SignalAPIClientProtocol: Sendable {
    func requestSignalAccess(name: String, deviceModel: String) async throws -> SignalAccessRequest
    func fetchSignalAccessRequest(requestToken: String) async throws -> SignalAccessRequest
    func fetchPasskeyRegistrationOptions(requestToken: String) async throws -> PasskeyRegistrationOptions
    func registerPasskey(_ credential: PasskeyRegistrationCredential, requestToken: String) async throws -> String
    func fetchPasskeyAuthenticationOptions() async throws -> PasskeyAuthenticationOptions
    func authenticatePasskey(_ credential: PasskeyAuthenticationCredential, ceremonyToken: String) async throws -> String
    func setSignal(topicID: Int, value: Int, bearerToken: String) async throws
}

public enum SignalAccessRequestStatus: String, Codable, Equatable, Sendable {
    case pending, declined, approved, revoked
}

public struct SignalAccessRequest: Codable, Equatable, Sendable {
    public let requestToken: String?
    public let status: SignalAccessRequestStatus
    public init(requestToken: String? = nil, status: SignalAccessRequestStatus) {
        self.requestToken = requestToken
        self.status = status
    }
    enum CodingKeys: String, CodingKey { case requestToken = "request_token", status }
}

public struct PasskeyCredentialDescriptor: Codable, Equatable, Sendable {
    public let type: String
    public let id: String
    public let transports: [String]?
    public init(type: String = "public-key", id: String, transports: [String]? = nil) {
        self.type = type
        self.id = id
        self.transports = transports
    }
}

public struct PasskeyRegistrationOptions: Codable, Equatable, Sendable {
    public struct RelyingParty: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }
    public struct User: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let displayName: String
        public init(id: String, name: String, displayName: String) {
            self.id = id; self.name = name; self.displayName = displayName
        }
    }
    public let challenge: String
    public let rp: RelyingParty
    public let user: User
    public let excludeCredentials: [PasskeyCredentialDescriptor]
    public init(challenge: String, rp: RelyingParty, user: User, excludeCredentials: [PasskeyCredentialDescriptor] = []) {
        self.challenge = challenge; self.rp = rp; self.user = user; self.excludeCredentials = excludeCredentials
    }
}

public struct PasskeyAuthenticationOptions: Codable, Equatable, Sendable {
    public let challenge: String
    public let rpID: String
    public let allowCredentials: [PasskeyCredentialDescriptor]
    public let ceremonyToken: String
    public init(challenge: String, rpID: String, allowCredentials: [PasskeyCredentialDescriptor] = [], ceremonyToken: String) {
        self.challenge = challenge; self.rpID = rpID; self.allowCredentials = allowCredentials; self.ceremonyToken = ceremonyToken
    }
    enum CodingKeys: String, CodingKey { case challenge, rpID = "rpId", allowCredentials, ceremonyToken = "ceremony_token" }
}

public struct PasskeyRegistrationCredential: Encodable, Equatable, Sendable {
    public struct Response: Encodable, Equatable, Sendable {
        public let clientDataJSON: String
        public let attestationObject: String
        public init(clientDataJSON: String, attestationObject: String) {
            self.clientDataJSON = clientDataJSON; self.attestationObject = attestationObject
        }
    }
    public let id: String
    public let rawID: String
    public let type = "public-key"
    public let response: Response
    public init(id: String, rawID: String, response: Response) { self.id = id; self.rawID = rawID; self.response = response }
    enum CodingKeys: String, CodingKey { case id, rawID = "rawId", type, response }
}

public struct PasskeyAuthenticationCredential: Encodable, Equatable, Sendable {
    public struct Response: Encodable, Equatable, Sendable {
        public let clientDataJSON: String
        public let authenticatorData: String
        public let signature: String
        public let userHandle: String?
        public init(clientDataJSON: String, authenticatorData: String, signature: String, userHandle: String?) {
            self.clientDataJSON = clientDataJSON; self.authenticatorData = authenticatorData
            self.signature = signature; self.userHandle = userHandle
        }
    }
    public let id: String
    public let rawID: String
    public let type = "public-key"
    public let response: Response
    public init(id: String, rawID: String, response: Response) { self.id = id; self.rawID = rawID; self.response = response }
    enum CodingKeys: String, CodingKey { case id, rawID = "rawId", type, response }
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
    case invalidAccessRequest
    case invalidSignalValue
    case invalidBearerToken
    case invalidResponse
    case httpStatus(Int)
    case transport(String)
    case decoding(String)
}

public final class URLSessionForumIndexAPIClient: APIClientProtocol, SignalAPIClientProtocol, Sendable {
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

    public func requestSignalAccess(name: String, deviceModel: String) async throws -> SignalAccessRequest {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = deviceModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedModel.isEmpty else { throw ForumIndexAPIError.invalidAccessRequest }
        let body = try JSONEncoder().encode(SignalAccessRequestBody(name: trimmedName, deviceModel: trimmedModel))
        return try decode(try await perform(path: "/api/v2/signal-access-requests", method: "POST", body: body))
    }

    public func fetchSignalAccessRequest(requestToken: String) async throws -> SignalAccessRequest {
        try await decode(perform(
            path: "/api/v2/signal-access-request", method: "GET", authorization: try authorization("Request", requestToken)
        ))
    }

    public func fetchPasskeyRegistrationOptions(requestToken: String) async throws -> PasskeyRegistrationOptions {
        try await decode(perform(
            path: "/api/v2/passkeys/registration-options", method: "POST", body: Data("{}".utf8),
            authorization: try authorization("Request", requestToken)
        ))
    }

    public func registerPasskey(_ credential: PasskeyRegistrationCredential, requestToken: String) async throws -> String {
        let data = try await perform(
            path: "/api/v2/passkeys/register",
            method: "POST",
            body: try JSONEncoder().encode(PasskeyRegistrationRequest(publicKeyCredential: credential)),
            authorization: try authorization("Request", requestToken)
        )
        return try bearerToken(data)
    }

    public func fetchPasskeyAuthenticationOptions() async throws -> PasskeyAuthenticationOptions {
        try await decode(perform(
            path: "/api/v2/passkeys/authentication-options", method: "POST", body: Data("{}".utf8)
        ))
    }

    public func authenticatePasskey(_ credential: PasskeyAuthenticationCredential, ceremonyToken: String) async throws -> String {
        let data = try await perform(
            path: "/api/v2/passkeys/authenticate",
            method: "POST",
            body: try JSONEncoder().encode(PasskeyAuthenticationRequest(
                ceremonyToken: ceremonyToken,
                publicKeyCredential: credential
            ))
        )
        return try bearerToken(data)
    }

    public func setSignal(topicID: Int, value: Int, bearerToken: String) async throws {
        guard topicID > 0, [-1, 0, 1].contains(value) else { throw ForumIndexAPIError.invalidSignalValue }
        guard !bearerToken.isEmpty,
              !bearerToken.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ForumIndexAPIError.invalidBearerToken
        }
        let body = try JSONEncoder().encode(SignalRequest(value: value))
        _ = try await perform(
            path: "/api/v2/topics/\(topicID)/signal",
            method: "PUT",
            body: body,
            authorization: try authorization("Bearer", bearerToken)
        )
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
        authorization: String? = nil
    ) async throws -> Data {
        try Task.checkCancellation()
        let url = try makeURL(path: path, queryItems: [], includesLanguage: false)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let authorization { urlRequest.setValue(authorization, forHTTPHeaderField: "Authorization") }

        return try await responseData(for: urlRequest)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw ForumIndexAPIError.decoding(String(describing: error)) }
    }

    private func bearerToken(_ data: Data) throws -> String {
        let token: SignalTokenResponse = try decode(data)
        guard !token.token.isEmpty else { throw ForumIndexAPIError.invalidResponse }
        return token.token
    }

    private func authorization(_ scheme: String, _ token: String) throws -> String {
        guard !token.isEmpty, !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ForumIndexAPIError.invalidAccessRequest
        }
        return "\(scheme) \(token)"
    }

    private func makeURL(
        path: String,
        queryItems: [URLQueryItem],
        includesLanguage: Bool = true
    ) throws -> URL {
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

private struct SignalAccessRequestBody: Encodable {
    let name: String
    let deviceModel: String
    enum CodingKeys: String, CodingKey {
        case name
        case deviceModel = "device_model"
    }
}

private struct SignalTokenResponse: Decodable { let token: String }
private struct SignalRequest: Encodable { let value: Int }
private struct PasskeyRegistrationRequest: Encodable {
    let publicKeyCredential: PasskeyRegistrationCredential
    enum CodingKeys: String, CodingKey { case publicKeyCredential = "public_key_credential" }
}
private struct PasskeyAuthenticationRequest: Encodable {
    let ceremonyToken: String
    let publicKeyCredential: PasskeyAuthenticationCredential
    enum CodingKeys: String, CodingKey {
        case ceremonyToken = "ceremony_token"
        case publicKeyCredential = "public_key_credential"
    }
}
