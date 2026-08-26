import Foundation

private enum WebURLPolicy {
    static func accepted(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    static func decode<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> URL? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return accepted(URL(string: value))
    }
}

public struct NavigationEnvelope: Codable, Equatable, Sendable {
    public let window: String
    public let count: Int
    public let subjectAreas: [SubjectArea]

    public init(window: String, count: Int? = nil, subjectAreas: [SubjectArea]) {
        self.window = window
        self.count = count ?? subjectAreas.count
        self.subjectAreas = subjectAreas
    }

    private enum CodingKeys: String, CodingKey {
        case window, count
        case subjectAreas = "areas"
    }
}

public struct SubjectArea: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let slug: String
    public let description: String
    public let position: Int
    public let topicCount: Int
    public let subjects: [ChildSubject]

    public init(
        id: Int,
        name: String,
        slug: String,
        topicCount: Int,
        subjects: [ChildSubject],
        description: String = "",
        position: Int = 0
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.description = description
        self.position = position
        self.topicCount = topicCount
        self.subjects = subjects
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, description, position, subjects
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

    public init(id: Int, title: String, url: URL?, excerpt: String?, forum: ForumSummary) {
        self.id = id
        self.title = title
        self.url = WebURLPolicy.accepted(url)
        self.excerpt = Self.nonEmpty(excerpt)
        self.forum = forum
    }

    private enum CodingKeys: String, CodingKey { case id, title, url, excerpt, forum }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = WebURLPolicy.decode(container, forKey: .url)
        excerpt = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .excerpt))
        forum = try container.decode(ForumSummary.self, forKey: .forum)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(url?.absoluteString, forKey: .url)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
        try container.encode(forum, forKey: .forum)
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

    public init(id: Int, name: String, slug: String, baseURL: URL?) {
        self.id = id
        self.name = name
        self.slug = slug
        self.baseURL = WebURLPolicy.accepted(baseURL)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug
        case baseURL = "base_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        baseURL = WebURLPolicy.decode(container, forKey: .baseURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(slug, forKey: .slug)
        try container.encodeIfPresent(baseURL?.absoluteString, forKey: .baseURL)
    }
}
