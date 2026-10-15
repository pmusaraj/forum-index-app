import SwiftUI

struct BookmarkIcon: View {
    var hasUnreadReplies = false

    var body: some View {
        Image(systemName: "bookmark")
            .overlay(alignment: .trailing) {
                if hasUnreadReplies {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: 6)
                }
            }
            .accessibilityLabel(hasUnreadReplies ? "Bookmark, new replies" : "Bookmark")
    }
}
