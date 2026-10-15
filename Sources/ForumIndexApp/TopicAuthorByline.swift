import ForumIndexCore
import SwiftUI

struct TopicAuthorByline: View {
    let post: MarkdownPost?
    let publishedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            if post?.username != nil {
                AsyncImage(url: post?.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let username = post?.username {
                    Text("@\(username)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                if let publishedAt {
                    Text(publishedAt, format: .dateTime.month(.abbreviated).day().year())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("topic-author-byline")
    }
}
