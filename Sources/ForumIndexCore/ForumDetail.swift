import Foundation

public struct ForumDetail: Decodable, Equatable, Sendable {
    public let forum: ForumSummary
    public let description: String?
    public let siteURL: URL?
    public let organizationURL: URL?

    private enum CodingKeys: String, CodingKey {
        case description
        case siteURL = "site_url"
        case organizationURL = "parent_site_url"
    }

    public init(from decoder: Decoder) throws {
        forum = try ForumSummary(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = ExcerptNormalizer.plainText(try container.decodeIfPresent(String.self, forKey: .description))
        siteURL = Self.webURL(try container.decodeIfPresent(String.self, forKey: .siteURL)) ?? forum.baseURL
        organizationURL = Self.webURL(try container.decodeIfPresent(String.self, forKey: .organizationURL))
    }

    private static func webURL(_ value: String?) -> URL? {
        guard let value else { return nil }
        return WebNavigationPolicy.acceptedURL(URL(string: value))
    }
}
