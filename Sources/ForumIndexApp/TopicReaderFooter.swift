import SwiftUI

struct TopicReaderFooter: View {
    let title: String
    let replyCount: Int?
    let participantCount: Int?
    let url: URL
#if os(macOS)
    @ScaledMetric(relativeTo: .body) private var readingFontSize = 17.0
    @ScaledMetric(relativeTo: .body) private var metadataFontSize = 15.0
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Rectangle()
                .fill(.secondary.opacity(0.4))
                .frame(height: 1.5)
                .accessibilityHidden(true)
            Text("You reached the end of topic: \(title) in \(url.host() ?? url.absoluteString)")
#if os(macOS)
                .font(.system(size: readingFontSize))
#else
                .font(.body)
#endif
                .fixedSize(horizontal: false, vertical: true)
            if !totals.isEmpty {
                Text(totals)
                    .foregroundStyle(.secondary)
            }
            Link(destination: url) {
                Label("Open in browser", systemImage: "arrow.up.right")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .environment(\.openURL, OpenURLAction { .systemAction($0) })
            .accessibilityHint("Opens this topic in your browser")
            .accessibilityIdentifier("topic-browser-footer")
        }
#if os(macOS)
        .font(.system(size: metadataFontSize))
#else
        .font(.subheadline)
#endif
        .padding(.top, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("topic-reader-footer")
    }

    private var totals: String {
        var values: [String] = []
        if let replyCount {
            values.append("\(replyCount) \(replyCount == 1 ? "reply" : "replies")")
        }
        if let participantCount {
            values.append("\(participantCount) \(participantCount == 1 ? "participant" : "participants")")
        }
        return values.joined(separator: " · ")
    }
}
