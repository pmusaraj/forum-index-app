import ForumIndexCore
import SwiftUI

struct ExternalSignalIcon: View {
    let source: ExternalSignal.Source
    @ScaledMetric(relativeTo: .footnote) private var size = 16.0

    var body: some View {
        Group {
            switch source {
            case .hackerNews:
                Text("Y")
                    .font(.system(size: size * 0.8, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Color(red: 1, green: 0.4, blue: 0))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            case .lobsters:
                Text("🦞")
                    .font(.system(size: size))
                    .frame(width: size + 2, height: size + 2)
            }
        }
        .accessibilityLabel(source.name)
    }
}

struct ExternalSignalLinks: View {
    let signals: [ExternalSignal]

    var body: some View {
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(signals.enumerated()), id: \.offset) { _, signal in
                    Link(destination: signal.url) {
                        HStack(spacing: 8) {
                            ExternalSignalIcon(source: signal.source)
                                .accessibilityHidden(true)
                            Text("Discuss on \(signal.source.name)")
                            Image(systemName: "arrow.up.right")
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint("Opens in Safari")
                    .accessibilityIdentifier("external-signal-\(signal.source.rawValue)")
                }
            }
            // Bypass the article's handler for internal Markdown navigation.
            .environment(\.openURL, OpenURLAction { .systemAction($0) })
        }
    }
}
