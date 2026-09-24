import ForumIndexCore
import SwiftUI
import Textual

struct TopicPostView: View {
    let post: MarkdownPost
    let baseURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let username = post.username {
                HStack(spacing: 8) {
                    AsyncImage(url: post.avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                    Text(username)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = post.publishedAt {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(PostRelativeDate.label(for: date, now: context.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .accessibilityLabel(date.formatted(date: .complete, time: .shortened))
                        }
                    }
                }
                .accessibilityIdentifier("post-author-\(post.id)")
            }
            StructuredText(markdown: post.markdown, baseURL: baseURL)
                .textual.inlineStyle(.gitHub.link(.foregroundColor(.accentColor)))
                .textual.blockQuoteStyle(TopicBlockQuoteStyle())
                .textual.structuredTextStyle(.gitHub)
                .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
                .textual.textSelection(.enabled)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
