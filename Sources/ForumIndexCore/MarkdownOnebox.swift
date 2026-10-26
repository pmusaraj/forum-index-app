import Foundation

/// Discourse exports oneboxes as a quote beginning with a standalone URL and a blank quote line.
/// The export has no HTML class metadata, so ordinary quotes and code blocks stay untouched.
public struct MarkdownOnebox: Equatable, Sendable, Identifiable {
    public let id: Int
    public let markdown: String
    public let isOnebox: Bool

    public static func segments(in markdown: String) -> [Self] {
        let lines = markdown.components(separatedBy: "\n")
        var segments: [Self] = []
        var start = 0
        var index = 0
        var fence: (Character, Int)?
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.drop(while: { $0 == " " })
            if line.count - trimmed.count <= 3, let character = trimmed.first,
               character == "`" || character == "~" {
                let count = trimmed.prefix(while: { $0 == character }).count
                if let current = fence {
                    if character == current.0, count >= current.1,
                       trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty {
                        fence = nil
                    }
                } else if count >= 3 {
                    fence = (character, count)
                }
                index += 1
                continue
            }
            guard fence == nil, (index == 0 || lines[index - 1].isEmpty),
                  line.hasPrefix("> <"), line.hasSuffix(">"),
                  let url = URL(string: String(line.dropFirst(3).dropLast())),
                  ["http", "https"].contains(url.scheme), url.host != nil,
                  index + 2 < lines.count,
                  lines[index + 1].trimmingCharacters(in: .whitespaces) == ">",
                  lines[index + 2].hasPrefix(">") else {
                index += 1
                continue
            }
            let quoteStart = index
            index += 1
            while index < lines.count, lines[index].hasPrefix(">") { index += 1 }
            if start < quoteStart {
                segments.append(Self(id: start, markdown: lines[start..<quoteStart].joined(separator: "\n"), isOnebox: false))
            }
            let body = lines[(quoteStart + 1)..<index].map { line in
                var value = line.dropFirst()
                if value.first == " " { value = value.dropFirst() }
                return String(value)
            }.joined(separator: "\n")
            // GitHub's preview body is raw Markdown escaped once by Discourse's HTML-to-Markdown export.
            let content = url.host?.lowercased() == "github.com" ? unescape(body) : body
            segments.append(Self(id: quoteStart, markdown: "<\(url.absoluteString)>\n\n\(content)", isOnebox: true))
            start = index
        }
        if start < lines.count {
            segments.append(Self(id: start, markdown: lines[start...].joined(separator: "\n"), isOnebox: false))
        }
        return segments
    }

    private static func unescape(_ value: String) -> String {
        let punctuation = CharacterSet(charactersIn: "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")
        let scalars = Array(value.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            if scalars[index] == "\\", index + 1 < scalars.count, punctuation.contains(scalars[index + 1]) {
                index += 1
            }
            result.append(scalars[index])
            index += 1
        }
        return String(result)
    }
}
