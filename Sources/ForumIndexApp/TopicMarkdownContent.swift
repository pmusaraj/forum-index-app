import ForumIndexCore
import SwiftUI
import Textual

struct TopicMarkdownContent: View {
    let markdown: String
    let baseURL: URL
    @Environment(\.openURL) private var openURL
    @State private var selectedImage: TopicImage?
#if os(macOS)
    @ScaledMetric(relativeTo: .body) private var readingFontSize = 17.0
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(TopicMarkdownSegments.shared.segments(in: markdown)) { segment in
                if segment.isOnebox {
                    TopicOneboxView(markdown: segment.markdown, baseURL: baseURL)
                } else {
                    StructuredText(segment.markdown, parser: TopicImageMarkdownParser(baseURL: baseURL))
                }
            }
        }
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
            .environment(\.openURL, OpenURLAction { destination in
                if let image = TopicImage(link: destination) {
                    selectedImage = image
                } else {
                    openURL(destination)
                }
                return .handled
            })
#if os(macOS)
            .sheet(item: $selectedImage) { TopicImageLightbox(image: $0) }
#else
            .fullScreenCover(item: $selectedImage) { TopicImageLightbox(image: $0) }
#endif
    }
}
