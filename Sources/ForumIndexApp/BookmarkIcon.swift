import SwiftUI

struct BookmarkIcon: View {
    var hasUnreadReplies = false

    var body: some View {
        Image(systemName: "bookmark")
            .overlay(alignment: .trailing) {
                if hasUnreadReplies {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 12, height: 12)
                        .frame(width: 6, alignment: .trailing)
                        .clipped()
                        .offset(x: 3)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(hasUnreadReplies ? "Bookmark, new replies" : "Bookmark")
    }
}
