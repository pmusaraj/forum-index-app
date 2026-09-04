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

    public static func externalURL(_ url: URL?, relativeTo pageURL: URL?) -> URL? {
        guard let url = acceptedURL(url),
              let pageURL = acceptedURL(pageURL),
              url.host?.caseInsensitiveCompare(pageURL.host ?? "") != .orderedSame else { return nil }
        return url
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
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    private var generation = 0

    public init() {}

    @discardableResult
    public mutating func beginLoading() -> Int {
        generation += 1
        isReady = false
        isLoading = true
        errorMessage = nil
        return generation
    }

    public mutating func commit(_ generation: Int) {
        guard generation == self.generation else { return }
        isReady = true
    }

    public mutating func finish(_ generation: Int) {
        guard generation == self.generation else { return }
        isReady = true
        isLoading = false
    }

    public mutating func fail(_ generation: Int, message: String) {
        guard generation == self.generation else { return }
        isReady = false
        isLoading = false
        errorMessage = message
    }

    public mutating func clear() {
        generation += 1
        isReady = false
        isLoading = false
        errorMessage = nil
    }
}

public struct ForumAssetWarmupState: Sendable {
    private var warmedForumIDs: Set<Int> = []

    public init() {}

    public mutating func assetURL(forForumID forumID: Int, topicURL: URL?) -> URL? {
        guard let topicURL = WebNavigationPolicy.acceptedURL(topicURL),
              var components = URLComponents(url: topicURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        guard let url = components.url, warmedForumIDs.insert(forumID).inserted else { return nil }
        return url
    }
}

public struct WebPageClearNavigationAllowance: Sendable {
    private var isPending = false

    public init() {}

    public mutating func begin() {
        isPending = true
    }

    public mutating func cancel() {
        isPending = false
    }

    public mutating func consumeIfAllowed(_ url: URL?) -> Bool {
        guard isPending, url?.absoluteString == "about:blank" else { return false }
        isPending = false
        return true
    }
}

public enum ForumPresentation {
    public static func displayName(_ name: String) -> String {
        let name = name == "OpenSource" ? "Open Source" : name
        return name.count > 60 ? String(name.prefix(59)) + "…" : name
    }

    public static func iconURL(for forum: ForumSummary) -> URL? {
        WebNavigationPolicy.acceptedURL(forum.iconURL)
    }

    public static func normalizedExcerpt(_ value: String?) -> String? {
        ExcerptNormalizer.plainText(value)
    }
}
