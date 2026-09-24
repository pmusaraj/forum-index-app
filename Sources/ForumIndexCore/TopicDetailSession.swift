import Foundation
import Observation

@MainActor
@Observable
public final class TopicDetailSession {
    public let topics: [Topic]
    public let orderedIDs: [TopicPresentationID]
    public let initialID: TopicPresentationID
    public private(set) var currentIndex: Int
    public private(set) var hasPaged = false

    public var currentTopic: Topic { topics[currentIndex] }
    public var currentID: TopicPresentationID { orderedIDs[currentIndex] }
    public var didChangeItem: Bool { currentID != initialID }

    public init?(topics: [Topic], selectedID: TopicPresentationID) {
        var seen: Set<TopicPresentationID> = []
        let navigable = topics.filter { $0.presentableURL != nil && seen.insert($0.presentationID).inserted }
        guard let index = navigable.firstIndex(where: { $0.presentationID == selectedID }) else { return nil }
        self.topics = navigable
        orderedIDs = navigable.map(\.presentationID)
        initialID = selectedID
        currentIndex = index
    }

    public func select(index: Int) {
        guard topics.indices.contains(index), index != currentIndex else { return }
        hasPaged = true
        currentIndex = index
    }
}
