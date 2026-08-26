import Foundation

public enum WebNavigationPolicy {
    public static func acceptedURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    public static func allows(_ url: URL?) -> Bool {
        acceptedURL(url) != nil
    }
}

public enum TopicActivationAction: Equatable, Sendable {
    case none
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

    var presentableURL: URL? {
        WebNavigationPolicy.acceptedURL(url)
    }
}

public struct TopicActivationState: Equatable, Sendable {
    public private(set) var destinationID: String?
    public private(set) var presentedURL: URL?

    public init(destinationID: String? = nil) {
        self.destinationID = destinationID
    }

    @discardableResult
    public mutating func activate(url: URL?) -> TopicActivationAction {
        guard let url = WebNavigationPolicy.acceptedURL(url) else {
            presentedURL = nil
            return .none
        }
        presentedURL = url
        return .present(url)
    }

    public mutating func destinationDidChange(to newDestinationID: String?) {
        guard destinationID != newDestinationID else { return }
        destinationID = newDestinationID
        presentedURL = nil
    }

    public mutating func dismissPresentation() {
        presentedURL = nil
    }
}

public enum ForumPresentation {
    public static func iconURL(for forum: ForumSummary) -> URL? {
        WebNavigationPolicy.acceptedURL(forum.iconURL)
    }

    public static func normalizedExcerpt(_ value: String?) -> String? {
        ExcerptNormalizer.plainText(value)
    }
}
