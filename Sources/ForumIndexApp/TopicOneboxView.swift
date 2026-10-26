import SwiftUI
import Textual

struct TopicOneboxView: View {
    let markdown: String
    let baseURL: URL
    @State private var isExpanded = false
    @State private var contentHeight: CGFloat = 0

    private let previewHeight: CGFloat = 200
    private var isOverflowing: Bool { contentHeight > previewHeight }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color("BrandSurface"))
                    .frame(width: 3)
                StructuredText(markdown, parser: TopicImageMarkdownParser(baseURL: baseURL))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .frame(height: isExpanded ? nil : min(contentHeight == 0 ? previewHeight : contentHeight, previewHeight), alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .mask {
                if !isExpanded && isOverflowing {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: 0.55),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    Rectangle()
                }
            }
            .accessibilityIdentifier("topic-onebox-content")

            if isOverflowing {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(isExpanded ? "Collapse preview" : "Expand preview",
                          systemImage: isExpanded ? "chevron.up" : "chevron.down")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("topic-onebox-toggle")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            }
        }
    }
}
