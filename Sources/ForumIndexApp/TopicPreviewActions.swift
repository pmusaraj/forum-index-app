import SwiftUI

struct TopicPreviewActions: View {
    let url: URL
    let isBookmarked: Bool
    let toggleBookmark: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share topic")
            Button(action: toggleBookmark) {
                Image(systemName: isBookmarked ? "star.fill" : "star")
            }
            .accessibilityLabel(isBookmarked ? "Unstar topic" : "Star topic")
            .accessibilityIdentifier("topic-web-star")
            Button("Dismiss topic", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
        }
        .modifier(WebActionButtonStyle())
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }
}
