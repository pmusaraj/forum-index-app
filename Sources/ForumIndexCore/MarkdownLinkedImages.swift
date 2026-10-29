import Foundation

/// Foundation preserves a linked image's label and source position, but loses its image URL.
public enum MarkdownLinkedImages {
    public static func restoringImages(
        in attributedString: AttributedString, markdown: String, baseURL: URL
    ) throws -> AttributedString {
        var result = attributedString
        for run in attributedString.runs {
            guard run.imageURL == nil, run.link != nil,
                  let position = run.markdownSourcePosition,
                  let range = Range(position, in: markdown) else { continue }
            let source = String(markdown[range])
            guard source.hasPrefix("![") else { continue }
            // Parse only the image span, leaving the surrounding link and block structure intact.
            let image = try AttributedString(markdown: source, baseURL: baseURL)
            if let url = image.runs.first?.imageURL {
                result[run.range].imageURL = url
            }
        }
        return result
    }
}
