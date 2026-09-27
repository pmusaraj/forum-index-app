import SwiftUI

struct TopicTitleElement: View {
    let title: String
    var isCompact = false

    var body: some View {
        Text(title)
            .font(isCompact ? .headline : .title2.weight(.bold))
            .lineLimit(isCompact ? 2 : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(isCompact ? "topic-sticky-title" : "topic-preview-title")
    }
}
