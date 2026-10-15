import SwiftUI

struct BookmarkIcon: View {
    var hasUnreadReplies = false

    var body: some View {
        Image(systemName: "bookmark")
            .overlay(alignment: .topTrailing) {
                if hasUnreadReplies {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: 7, y: -3)
                }
            }
            .accessibilityLabel(hasUnreadReplies ? "Bookmark, new replies" : "Bookmark")
    }
}
