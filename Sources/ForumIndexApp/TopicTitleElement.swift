import SwiftUI

struct TopicTitleElement: View {
    let title: String
    var isCompact = false
    @Environment(\.readerTypography) private var typography
    @ScaledMetric(relativeTo: .title2) private var titleScale = 1.0

    private var titleFont: Font {
        if isCompact { return .headline }
        return .system(size: typography.titleSize * titleScale, weight: .semibold)
    }

    var body: some View {
        Text(title)
            .font(titleFont)
            .lineLimit(isCompact ? 2 : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(isCompact ? "topic-sticky-title" : "topic-preview-title")
    }
}
