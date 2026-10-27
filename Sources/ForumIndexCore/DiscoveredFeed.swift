import Foundation

public struct DiscoveredFeed: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let path: String
    public let personalized: Bool

    public init(id: String, name: String, description: String, path: String, personalized: Bool) {
        self.id = id
        self.name = name
        self.description = description
        self.path = path
        self.personalized = personalized
    }
}
