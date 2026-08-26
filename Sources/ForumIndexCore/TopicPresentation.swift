import Foundation

public enum TopicActivationAction: Equatable, Sendable {
    case none
    case preload(URL)
    case present(URL)
}

public struct TopicPresentationID: Hashable, Sendable {
    public let forumID: Int
    public let topicID: Int

    public init(forumID: Int, topicID: Int) {
        self.forumID = forumID
        self.topicID = topicID
    }
}

public extension Topic {
    var presentationID: TopicPresentationID {
        TopicPresentationID(forumID: forum.id, topicID: id)
    }
}

public struct TopicActivationState: Equatable, Sendable {
    public private(set) var destinationID: String?
    public private(set) var expandedTopicID: TopicPresentationID?
    public private(set) var presentedURL: URL?
    private var armedURL: URL?

    public init(destinationID: String? = nil) {
        self.destinationID = destinationID
    }

    @discardableResult
    public mutating func activate(topicID: TopicPresentationID, url: URL?) -> TopicActivationAction {
        if expandedTopicID != topicID {
            expandedTopicID = topicID
            presentedURL = nil
            armedURL = Self.acceptedWebURL(url)
            return armedURL.map(TopicActivationAction.preload) ?? .none
        }

        guard let armedURL else {
            presentedURL = nil
            return .none
        }
        presentedURL = armedURL
        return .present(armedURL)
    }

    public mutating func destinationDidChange(to newDestinationID: String?) {
        guard destinationID != newDestinationID else { return }
        destinationID = newDestinationID
        expandedTopicID = nil
        presentedURL = nil
        armedURL = nil
    }

    public mutating func dismissPresentation() {
        presentedURL = nil
    }

    private static func acceptedWebURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}

public enum ForumPresentation {
    public static func faviconURL(for baseURL: URL?) -> URL? {
        guard let baseURL,
              let scheme = baseURL.scheme?.lowercased(),
              scheme == "https",
              baseURL.host != nil,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    public static func monogram(for name: String) -> String {
        guard let character = name.first(where: { character in
            character.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
        }) else { return "?" }
        return String(character).uppercased()
    }

    public static func normalizedExcerpt(_ value: String?) -> String? {
        ExcerptNormalizer.plainText(value)
    }
}
