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
                Image(systemName: isBookmarked ? "star.fill" : "star")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isBookmarked ? Color.accentColor : Color.primary)
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isBookmarked)
                    .symbolEffectsRemoved(reduceMotion)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isBookmarked)
            }
            .accessibilityLabel(isBookmarked ? "Unstar topic" : "Star topic")
            .accessibilityIdentifier("topic-web-star")
            .accessibilityValue(isBookmarked ? "Starred" : "Not starred")
            Button("Dismiss topic", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
        }
        .modifier(WebActionButtonStyle())
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }
}
