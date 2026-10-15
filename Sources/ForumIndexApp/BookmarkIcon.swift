import SwiftUI

struct BookmarkIcon: View {
    var hasUnreadReplies = false

    var body: some View {
        Image(systemName: "bookmark")
            .overlay(alignment: .topTrailing) {
                if hasUnreadReplies {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: 6, y: -2)
                }
            }
            .accessibilityLabel(hasUnreadReplies ? "Bookmark, new replies" : "Bookmark")
    }
}
