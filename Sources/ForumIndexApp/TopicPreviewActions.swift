import SwiftUI

struct TopicPreviewActions: View {
    let url: URL
    let isBookmarked: Bool
    let toggleBookmark: () -> Void
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share topic")
            Button(action: toggleBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isBookmarked ? Color.accentColor : Color.primary)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isBookmarked)
                    .symbolEffectsRemoved(reduceMotion)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isBookmarked)
            }
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark topic")
            .accessibilityIdentifier("topic-web-star")
            .accessibilityValue(isBookmarked ? "Bookmarked" : "Not bookmarked")
            Button("Dismiss topic", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
        }
        .modifier(WebActionButtonStyle())
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }
}
