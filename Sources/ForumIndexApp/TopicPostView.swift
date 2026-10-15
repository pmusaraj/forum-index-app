import ForumIndexCore
import SwiftUI

struct TopicPostView: View {
    let post: MarkdownPost
    let baseURL: URL
#if os(macOS)
    @ScaledMetric(relativeTo: .body) private var metadataFontSize = 15.0
#endif

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
                    Text("@\(username)")
#if os(macOS)
                        .font(.system(size: metadataFontSize, weight: .semibold))
#else
                        .font(.subheadline.weight(.semibold))
#endif
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = post.publishedAt {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(PostRelativeDate.label(for: date, now: context.date))
#if os(macOS)
                                .font(.system(size: metadataFontSize))
#else
                                .font(.caption)
#endif
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: true, vertical: false)
                                .accessibilityLabel(date.formatted(date: .complete, time: .shortened))
                        }
                    }
                }
                .accessibilityIdentifier("post-author-\(post.id)")
            }
            TopicMarkdownContent(markdown: post.markdown, baseURL: baseURL)
        }
    }
}
