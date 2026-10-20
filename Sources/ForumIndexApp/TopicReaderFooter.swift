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
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(height: 1)
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(height: 1)
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("End of topic")
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("topic-end-heading")
                Text(title)
#if os(macOS)
                    .font(.system(size: readingFontSize, weight: .semibold))
#else
                    .font(.headline)
#endif
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("topic-footer-title")
                Text(url.host() ?? url.absoluteString)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !totals.isEmpty {
                Text(totals)
                    .foregroundStyle(.secondary)
            }
            Link(destination: url) {
                Label("Open in browser", systemImage: "arrow.up.right")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 12)
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
