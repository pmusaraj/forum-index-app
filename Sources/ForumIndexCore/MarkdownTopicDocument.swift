import Foundation

/// Interprets Discourse's generated envelope, leaving each post's Markdown intact.
public struct MarkdownTopicDocument: Equatable, Sendable {
    public let title: String?
    public let posts: [MarkdownPost]
    public let nextPageURL: URL?

    public init(markdown: String, baseURL: URL? = nil, postIDOffset: Int = 0) {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let hasEnvelope = lines.first?.hasPrefix("# ") == true
            && lines.dropFirst().first(where: { !$0.isEmpty })?.hasPrefix("**URL:**") == true
        title = hasEnvelope ? lines.first.map { String($0.dropFirst(2)) } : nil
        var posts: [MarkdownPost] = []
        var nextPageURL: URL?
        var footer: [Int: String] = [:]
        // Only consume navigation at the end of a generated topic document.
        if lines.first?.hasPrefix("# ") == true,
           lines.dropFirst().first(where: { !$0.isEmpty })?.hasPrefix("**URL:**") == true {
            for index in lines.indices.reversed() {
                if lines[index].trimmingCharacters(in: .whitespaces).isEmpty { continue }
                guard Self.capture(#"^\[(?:Next|Previous) page\]\(([^\s)]+)\)$"#, in: lines[index]) != nil else { break }
                footer[index] = lines[index]
            }
        }
        var body: [String] = []
        var metadata: (username: String?, avatarURL: URL?, date: Date?)?
        var index = 0
        var fence: (character: Character, count: Int)?

        func appendPost(beforeMetadata: Bool) {
            var content = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            // Discourse inserts a thematic break between posts.
            if beforeMetadata, content.hasSuffix("\n\n---") {
                content.removeLast(5)
            }
            if metadata == nil, posts.isEmpty {
                content = Self.removingTopicEnvelope(content)
            }
            guard metadata != nil || !content.isEmpty else { return }
            posts.append(MarkdownPost(
                id: postIDOffset + posts.count, username: metadata?.username, avatarURL: metadata?.avatarURL,
                publishedAt: metadata?.date, markdown: content
            ))
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let character = trimmed.first, character == "`" || character == "~" {
                let count = trimmed.prefix(while: { $0 == character }).count
                if let current = fence {
                    if character == current.character, count >= current.count,
                       trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                        fence = nil
                    }
                } else if count >= 3 {
                    fence = (character, count)
                }
                body.append(line)
                index += 1
                continue
            }
            if fence == nil, let navigation = footer[index] {
                if let destination = Self.capture(#"^\[Next page\]\(([^\s)]+)\)$"#, in: navigation) {
                    nextPageURL = WebNavigationPolicy.acceptedURL(URL(string: destination, relativeTo: baseURL)?.absoluteURL)
                }
                index += 1
                continue
            }
            if fence == nil, hasEnvelope, let legacy = Self.legacyMarkdownMetadata(line) {
                appendPost(beforeMetadata: true)
                body = []
                metadata = (legacy.username, nil, legacy.date)
                index += 1
            } else if fence == nil,
               ["<div class=\"post-metadata\">", "<div class='post-metadata'>"].contains(line),
               let end = lines[(index + 1)...].firstIndex(of: "</div>"),
               let authorLine = lines[(index + 1)..<end].first(where: { $0.hasPrefix("### Author:") }) {
                appendPost(beforeMetadata: true)
                body = []
                let dateLine = lines[(index + 1)..<end].first(where: { $0.hasPrefix("#### Post date:") }) ?? ""
                let username = Self.capture(#"\[@((?:\\.|[^\]])+)\]\("#, in: authorLine)?
                    .replacingOccurrences(of: #"\_"#, with: "_")
                let avatar = Self.capture(#"!\[[^\]]*\]\(([^\s)]+)\)"#, in: authorLine)
                let timestamp = Self.capture(#""([0-9]{4}-[^"\s]+)""#, in: dateLine)
                metadata = (username, WebNavigationPolicy.acceptedURL(avatar.flatMap(URL.init(string:))), timestamp.flatMap(Self.date))
                index = end + 1
            } else {
                body.append(line)
                index += 1
            }
        }
        appendPost(beforeMetadata: false)
        self.posts = posts
        self.nextPageURL = nextPageURL
    }

    private static func removingTopicEnvelope(_ input: String) -> String {
        var lines = input.components(separatedBy: "\n")
        // Only remove the known generated envelope, not arbitrary headings in a post.
        guard lines.first?.hasPrefix("# ") == true,
              lines.dropFirst().first(where: { !$0.isEmpty })?.hasPrefix("**URL:**") == true else { return input }
        lines.removeFirst()
        let fields = ["**URL:**", "**Category:**", "**Tags:**", "**Created:**", "**Posts:**", "**Posts on this page:**", "**Page:**", "**Showing post:**"]
        while let line = lines.first, line.isEmpty || fields.contains(where: { line.hasPrefix($0) }) {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Legacy markdown plugins emit a heading instead of a post-metadata div.
    private static func legacyMarkdownMetadata(_ line: String) -> (username: String, date: Date)? {
        let pattern = #"^## Post [0-9]+ by @([^\s]+) — ([0-9]{4}-[^\s]+)$"#
        guard let username = capture(pattern, in: line),
              let timestamp = capture(#" — ([0-9]{4}-[^\s]+)$"#, in: line),
              let date = date(timestamp) else { return nil }
        return (username.replacingOccurrences(of: #"\_"#, with: "_"), date)
    }

    private static func capture(_ pattern: String, in input: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let range = Range(match.range(at: 1), in: input) else { return nil }
        return String(input[range])
    }

    private static func date(_ timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
    }
}
