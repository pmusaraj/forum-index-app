import Foundation
import ForumIndexCore
import Textual

/// Uses the renderer's native link hit testing, including its text-selection overlays.
struct TopicImageMarkdownParser: MarkupParser {
    let baseURL: URL

    func attributedString(for input: String) throws -> AttributedString {
        let parsed = try AttributedStringMarkdownParser(
            baseURL: baseURL, options: .init(appliesSourcePositionAttributes: true)
        ).attributedString(for: input)
        var result = try MarkdownLinkedImages.restoringImages(in: parsed, markdown: input, baseURL: baseURL)
        for run in result.runs {
            guard let source = run.imageURL,
                  let url = URL(string: source.relativeString, relativeTo: baseURL)?.absoluteURL else { continue }
            // A linked thumbnail opens its original image. Images linking to webpages keep that navigation.
            let destination = run.link.flatMap { URL(string: $0.relativeString, relativeTo: baseURL)?.absoluteURL }
            if let destination, !["png", "jpg", "jpeg", "gif", "webp", "avif", "heic"].contains(destination.pathExtension.lowercased()) {
                continue
            }
            let image = TopicImage(url: destination ?? url, label: String(result[run.range].characters))
            result[run.range].link = image.link
        }
        return result
    }
}
