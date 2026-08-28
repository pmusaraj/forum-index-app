import Foundation

private enum WebURLDecoder {
    static func decode<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> URL? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return WebNavigationPolicy.acceptedURL(URL(string: value))
    }
}

private enum APIDate {
    static func decode<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> Date? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func encode(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public struct NavigationEnvelope: Codable, Equatable, Sendable {
    public let version: String
    public let window: String
    public let count: Int
    public let subjectAreas: [SubjectArea]

    public init(version: String = "v1", window: String, count: Int? = nil, subjectAreas: [SubjectArea]) {
        self.version = version
        self.window = window
        self.count = count ?? subjectAreas.count
        self.subjectAreas = subjectAreas
    }

    private enum CodingKeys: String, CodingKey {
        case version, window, count, subjects
        case subjectAreas = "areas"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "v1"
        window = try container.decode(String.self, forKey: .window)
        subjectAreas = try container.decodeIfPresent([SubjectArea].self, forKey: .subjectAreas)
            ?? container.decode([SubjectArea].self, forKey: .subjects)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? subjectAreas.count
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(window, forKey: .window)
        try container.encode(count, forKey: .count)
        if version == "v2" {
            try container.encode(subjectAreas, forKey: .subjects)
        } else {
            try container.encode(subjectAreas, forKey: .subjectAreas)
        }
    }
}

public struct SubjectArea: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let slug: String
    public let description: String
    public let position: Int
    public let secondary: Bool
    public let topicCount: Int
    public let subjects: [ChildSubject]

    public init(
        id: Int,
        name: String,
        slug: String,
        topicCount: Int,
        subjects: [ChildSubject],
        description: String = "",
        position: Int = 0,
        secondary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.position = position
        self.secondary = secondary
        self.topicCount = topicCount
        self.subjects = subjects
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, description, position, secondary, subjects
        case topicCount = "topic_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        secondary = try container.decodeIfPresent(Bool.self, forKey: .secondary) ?? false
        topicCount = try container.decode(Int.self, forKey: .topicCount)
        subjects = try container.decodeIfPresent([ChildSubject].self, forKey: .subjects) ?? []
    }
}

public struct ChildSubject: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let slug: String
    public let description: String
    public let position: Int
    public let topicCount: Int

    public init(
        id: Int,
        name: String,
        slug: String,
        topicCount: Int,
        description: String = "",
        position: Int = 0
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.position = position
        self.topicCount = topicCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, description, position
        case topicCount = "topic_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        position = try container.decodeIfPresent(Int.self, forKey: .position) ?? 0
        topicCount = try container.decode(Int.self, forKey: .topicCount)
    }
}

public struct TopicFeedEnvelope: Codable, Equatable, Sendable {
    public let subjectArea: FeedSubjectMetadata?
    public let subject: FeedSubjectMetadata?
    public let count: Int
    public let results: [Topic]

    public init(subjectArea: FeedSubjectMetadata? = nil, subject: FeedSubjectMetadata? = nil, count: Int, results: [Topic]) {
        self.subjectArea = subjectArea
        self.subject = subject
        self.count = count
        self.results = results
    }

    private enum CodingKeys: String, CodingKey {
        case subjectArea = "subject_area"
        case subject, count, results
    }
}

public struct FeedSubjectMetadata: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let slug: String

    public init(id: Int, name: String, slug: String) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

public struct Topic: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let url: URL?
    public let excerpt: String?
    public let forum: ForumSummary
    public let publishedAt: Date?
    public let replyCount: Int

    public init(
        id: Int,
        title: String,
        url: URL?,
        excerpt: String?,
        forum: ForumSummary,
        publishedAt: Date? = nil,
        replyCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.url = WebNavigationPolicy.acceptedURL(url)
        self.excerpt = Self.nonEmpty(excerpt)
        self.forum = forum
        self.publishedAt = publishedAt
        self.replyCount = max(replyCount, 0)
    }

    private struct Engagement: Codable {
        let replies: Int
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, url, excerpt, forum, engagement
        case publishedAt = "published_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = WebURLDecoder.decode(container, forKey: .url)
        excerpt = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .excerpt))
        forum = try container.decode(ForumSummary.self, forKey: .forum)
        publishedAt = APIDate.decode(container, forKey: .publishedAt)
        replyCount = max((try? container.decodeIfPresent(Engagement.self, forKey: .engagement)?.replies) ?? 0, 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(url?.absoluteString, forKey: .url)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
        try container.encode(forum, forKey: .forum)
        if let publishedAt {
            try container.encode(APIDate.encode(publishedAt), forKey: .publishedAt)
        }
        try container.encode(Engagement(replies: replyCount), forKey: .engagement)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

public struct ForumSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let slug: String
    public let baseURL: URL?
    public let iconURL: URL?

    public init(id: Int, name: String, slug: String, baseURL: URL?, iconURL: URL? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.baseURL = WebNavigationPolicy.acceptedURL(baseURL)
        self.iconURL = WebNavigationPolicy.acceptedURL(iconURL)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug
        case baseURL = "base_url"
        case iconURL = "icon_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        baseURL = WebURLDecoder.decode(container, forKey: .baseURL)
        iconURL = WebURLDecoder.decode(container, forKey: .iconURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(slug, forKey: .slug)
        try container.encodeIfPresent(baseURL?.absoluteString, forKey: .baseURL)
        try container.encodeIfPresent(iconURL?.absoluteString, forKey: .iconURL)
    }
}
