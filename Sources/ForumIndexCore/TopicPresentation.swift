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

public struct WebPageLoadState: Equatable, Sendable {
    public private(set) var isReady = false
    public private(set) var errorMessage: String?
    private var generation = 0

    public init() {}

    @discardableResult
    public mutating func beginLoading() -> Int {
        generation += 1
        isReady = false
        errorMessage = nil
        return generation
    }

    public mutating func commit(_ generation: Int) {
        guard generation == self.generation else { return }
        isReady = true
    }

    public mutating func fail(_ generation: Int, message: String) {
        guard generation == self.generation else { return }
        isReady = false
        errorMessage = message
    }

    public mutating func clear() {
        _ = beginLoading()
    }
}

public enum ForumPresentation {
    public static func displayName(_ name: String) -> String {
        name.count > 60 ? String(name.prefix(59)) + "…" : name
    }

    public static func shouldShowDate(
        _ date: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let date else { return false }
        return !calendar.isDate(date, inSameDayAs: now)
    }

    public static func iconURL(for forum: ForumSummary) -> URL? {
        WebNavigationPolicy.acceptedURL(forum.iconURL)
    }

    public static func normalizedExcerpt(_ value: String?) -> String? {
        ExcerptNormalizer.plainText(value)
    }
}
