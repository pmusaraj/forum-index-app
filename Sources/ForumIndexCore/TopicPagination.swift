import Foundation

public enum TopicPagination {
    public static func isNearEnd(contentHeight: Double, visibleBottom: Double, viewportHeight: Double) -> Bool {
        viewportHeight > 0 && contentHeight - visibleBottom <= viewportHeight
    }

    static func pageNumber(_ url: URL) -> Int? {
        URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems?
            .first(where: { $0.name == "page" })?.value.flatMap(Int.init)
    }

    static func nextURL(_ candidate: URL?, for topicURL: URL, after page: Int) -> URL? {
        guard let candidate = WebNavigationPolicy.acceptedURL(candidate),
              candidate.host?.lowercased() == topicURL.host?.lowercased(),
              (candidate.port ?? 443) == (topicURL.port ?? 443),
              candidate.path.replacingOccurrences(of: #"\.md$"#, with: "", options: .regularExpression)
                == topicURL.path.replacingOccurrences(of: #"\.md$"#, with: "", options: .regularExpression),
              let nextPage = pageNumber(candidate), nextPage > page else { return nil }
        return candidate
    }
}
