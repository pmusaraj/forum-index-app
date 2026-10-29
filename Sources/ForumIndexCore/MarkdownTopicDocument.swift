import Foundation

/// Interprets Discourse's generated envelope, leaving each post's Markdown intact.
public struct MarkdownTopicDocument: Equatable, Sendable {
    public let title: String?
    public let summary: String?
    public let startsTopic: Bool
    public let hasNextPage: Bool
    public let posts: [MarkdownPost]
    public let nextPageURL: URL?
    public let previousPageURL: URL?
    public let pageNumber: Int

    public static func parse(markdown: String, baseURL: URL, postIDOffset: Int = 0) async throws -> Self {
        let task = Task.detached(priority: Task.currentPriority) {
            try Task.checkCancellation()
            return Self(markdown: markdown, baseURL: baseURL, postIDOffset: postIDOffset)
        }
        return try await withTaskCancellationHandler {
            let document = try await task.value
            try Task.checkCancellation()
            return document
        } onCancel: {
            task.cancel()
        }
    }

    public init(markdown: String, baseURL: URL? = nil, postIDOffset: Int = 0) {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let hasEnvelope = lines.first?.hasPrefix("# ") == true
            && lines.dropFirst().first(where: { !$0.isEmpty })?.hasPrefix("**URL:**") == true
        title = hasEnvelope ? lines.first.map { String($0.dropFirst(2)) } : nil
        let envelope = hasEnvelope ? Array(lines.dropFirst().prefix {
            $0.isEmpty || Self.envelopeFields.contains(where: $0.hasPrefix)
        }) : []
        let startsTopic = hasEnvelope
            && !envelope.contains(where: { $0.hasPrefix("**Showing post:**") })
            && !envelope.contains(where: {
                $0.hasPrefix("**Page:**") && Self.capture(#"^\*\*Page:\*\* ([0-9]+)"#, in: $0) != "1"
            })
        var summary: String?
        var posts: [MarkdownPost] = []
        var nextPageURL: URL?
        var previousPageURL: URL?
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
        var metadata: (username: String?, avatarURL: URL?, date: Date?, number: Int?)?
        var index = 0
        var fence: (character: Character, count: Int)?

        func appendPost(beforeMetadata: Bool) {
            var content = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            // Discourse inserts a thematic break between posts.
            if beforeMetadata, metadata != nil, content.hasSuffix("\n\n---") {
                content.removeLast(5)
            }
            if metadata == nil, posts.isEmpty {
                content = Self.removingTopicEnvelope(content)
                // Only recognize the generated summary before the first real author row.
                // A matching heading inside a post or ordinary Markdown remains untouched.
                let heading = "## AI-generated summary"
                if startsTopic, beforeMetadata,
                   content.components(separatedBy: "\n").first == heading {
                    let value = String(content.dropFirst(heading.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { summary = value }
                    return
                }
            }
            guard metadata != nil || !content.isEmpty else { return }
            posts.append(MarkdownPost(
                id: metadata?.number ?? -(postIDOffset + posts.count + 1), username: metadata?.username, avatarURL: metadata?.avatarURL,
                publishedAt: metadata?.date, markdown: content, postNumber: metadata?.number
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
                if let destination = Self.capture(#"^\[Previous page\]\(([^\s)]+)\)$"#, in: navigation) {
                    previousPageURL = WebNavigationPolicy.acceptedURL(URL(string: destination, relativeTo: baseURL)?.absoluteURL)
                }
                index += 1
                continue
            }
            if fence == nil, hasEnvelope, let legacy = Self.legacyMarkdownMetadata(line) {
                appendPost(beforeMetadata: true)
                body = []
                metadata = (legacy.username, nil, legacy.date, Self.capture(#"^## Post ([0-9]+) by"#, in: line).flatMap(Int.init))
                index += 1
            } else if fence == nil,
               ["<div class=\"post-metadata\">", "<div class='post-metadata'>"].contains(line),
               let end = lines[(index + 1)...].firstIndex(of: "</div>"),
               let authorLine = lines[(index + 1)..<end].first(where: {
                   $0.hasPrefix("### Author:") || $0.hasPrefix("**Author:**")
               }) {
                appendPost(beforeMetadata: true)
                body = []
                let dateLine = lines[(index + 1)..<end].first(where: {
                    $0.hasPrefix("#### Post date:") || $0.hasPrefix("**Post date:**")
                }) ?? ""
                let username = Self.capture(#"\[@((?:\\.|[^\]])+)\]\("#, in: authorLine)?
                    .replacingOccurrences(of: #"\_"#, with: "_")
                let avatar = Self.capture(#"!\[[^\]]*\]\(([^\s)]+)\)"#, in: authorLine)
                let timestamp = Self.capture(#""([0-9]{4}-[^"\s]+)""#, in: dateLine)
                let permalink = Self.capture(#"\]\(([^\s)]+)"#, in: dateLine)
                let number = permalink.flatMap { URL(string: $0, relativeTo: baseURL) }.flatMap {
                    Self.capture(#"/t/(?:[^/]+/)?[0-9]+/([0-9]+)/?$"#, in: $0.path).flatMap(Int.init)
                }
                metadata = (username, WebNavigationPolicy.acceptedURL(avatar.flatMap(URL.init(string:))), timestamp.flatMap(Self.date), number)
                index = end + 1
            } else {
                body.append(line)
                index += 1
            }
        }
        appendPost(beforeMetadata: false)
        self.summary = summary
        self.startsTopic = startsTopic && !footer.values.contains(where: { $0.hasPrefix("[Previous page]") })
        self.hasNextPage = footer.values.contains(where: { $0.hasPrefix("[Next page]") })
        self.posts = posts
        self.nextPageURL = nextPageURL
        self.previousPageURL = previousPageURL
        self.pageNumber = envelope.compactMap { Self.capture(#"^\*\*Page:\*\* ([0-9]+)"#, in: $0).flatMap(Int.init) }.first ?? 1
    }

    private static let envelopeFields = ["**URL:**", "**Category:**", "**Tags:**", "**Created:**", "**Posts:**", "**Posts on this page:**", "**Page:**", "**Showing post:**"]

    private static func removingTopicEnvelope(_ input: String) -> String {
        var lines = input.components(separatedBy: "\n")
        // Only remove the known generated envelope, not arbitrary headings in a post.
        guard lines.first?.hasPrefix("# ") == true,
              lines.dropFirst().first(where: { !$0.isEmpty })?.hasPrefix("**URL:**") == true else { return input }
        lines.removeFirst()
        while let line = lines.first, line.isEmpty || envelopeFields.contains(where: { line.hasPrefix($0) }) {
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
