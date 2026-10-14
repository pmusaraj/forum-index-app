import SwiftUI
import Textual

struct TopicMarkdownContent: View {
    let markdown: String
    let baseURL: URL
#if os(macOS)
    @ScaledMetric(relativeTo: .body) private var readingFontSize = 17.0
#endif

    var body: some View {
        StructuredText(markdown: markdown, baseURL: baseURL)
            .textual.inlineStyle(
                .gitHub
                    .code(.monospaced, .fontScale(0.85), .backgroundColor(Color("BrandSurface")))
                    .link(.foregroundColor(.accentColor))
            )
            .textual.blockQuoteStyle(TopicBlockQuoteStyle())
            .textual.thematicBreakStyle(TopicThematicBreakStyle())
            .textual.structuredTextStyle(.gitHub)
            .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
            .textual.textSelection(.enabled)
#if os(macOS)
            .font(.system(size: readingFontSize))
#else
            .font(.body)
#endif
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
