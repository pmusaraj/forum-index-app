import Foundation

struct TopicImage: Identifiable {
    let url: URL
    let label: String
    var id: URL { url }

    var link: URL? {
        var components = URLComponents()
        components.scheme = "forum-index-image"
        components.host = "preview"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString),
                                 URLQueryItem(name: "label", value: label)]
        return components.url
    }

    init(url: URL, label: String) {
        self.url = url
        self.label = label.isEmpty ? "Image" : label
    }

    init?(link: URL) {
        guard link.scheme == "forum-index-image",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let value = items.first(where: { $0.name == "url" })?.value,
              let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        self.init(url: url, label: items.first(where: { $0.name == "label" })?.value ?? "Image")
    }
}
