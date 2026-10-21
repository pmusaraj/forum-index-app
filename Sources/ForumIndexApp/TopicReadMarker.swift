import ForumIndexCore
import SwiftUI

/// A post counts as read once its bottom remains visible briefly in the active reader.
struct TopicReadMarker: View {
    let post: MarkdownPost
    let isActive: Bool
    let onRead: (MarkdownPost) -> Void
    @State private var isVisible = false

    var body: some View {
        Color.clear
            .frame(height: 1)
            .onScrollVisibilityChange(threshold: 1) { isVisible = $0 }
            .task(id: isActive && isVisible) {
                guard isActive, isVisible else { return }
                do {
                    try await Task.sleep(for: .milliseconds(750))
                    try Task.checkCancellation()
                    onRead(post)
                } catch { }
            }
            .accessibilityHidden(true)
    }
}
