import Foundation

public struct SubjectSelection: Codable {
    public var orderedIDs: [String]
    public var forYouIntroduced: Bool? = nil
    public var introducedFeedIDs: [String]? = nil

    public init(orderedIDs: [String], forYouIntroduced: Bool? = nil, introducedFeedIDs: [String]? = nil) {
        self.orderedIDs = orderedIDs
        self.forYouIntroduced = forYouIntroduced
        self.introducedFeedIDs = introducedFeedIDs
    }

    public mutating func introduceFeeds(_ ids: [String]) {
        var known = Set(introducedFeedIDs ?? [])
        for id in ids where known.insert(id).inserted {
            if !orderedIDs.contains(id) { orderedIDs.append(id) }
        }
        introducedFeedIDs = known.sorted()
    }

    public static func load(from data: Data) -> SubjectSelection? {
        try? JSONDecoder().decode(Self.self, from: data)
    }

    public var data: Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

