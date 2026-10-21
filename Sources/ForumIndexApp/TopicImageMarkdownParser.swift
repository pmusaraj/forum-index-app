import Foundation
import Textual

/// Uses the renderer's native link hit testing, including its text-selection overlays.
struct TopicImageMarkdownParser: MarkupParser {
    let baseURL: URL

    func attributedString(for input: String) throws -> AttributedString {
        var result = try AttributedStringMarkdownParser(baseURL: baseURL).attributedString(for: input)
        for run in result.runs {
            guard let source = run.imageURL,
                  let url = URL(string: source.relativeString, relativeTo: baseURL)?.absoluteURL else { continue }
            let image = TopicImage(url: url, label: String(result[run.range].characters))
            result[run.range].link = image.link
        }
        return result
    }
}
