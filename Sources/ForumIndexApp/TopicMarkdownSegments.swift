import ForumIndexCore

/// Memoizes immutable segmentation without an extra state/layout pass when posts appear.
@MainActor
final class TopicMarkdownSegments {
    static let shared = TopicMarkdownSegments()
    private var entries: [String: [MarkdownOnebox]] = [:]
    private var recency: [String] = []
    private var sourceBytes = 0
    private let maximumBytes = 2 * 1024 * 1024

    func segments(in markdown: String) -> [MarkdownOnebox] {
        if let segments = entries[markdown] {
            touch(markdown)
            return segments
        }
        let segments = MarkdownOnebox.segments(in: markdown)
        let bytes = markdown.utf8.count
        guard bytes <= maximumBytes else { return segments }
        entries[markdown] = segments
        sourceBytes += bytes
        touch(markdown)
        while entries.count > 64 || sourceBytes > maximumBytes {
            let oldest = recency.removeFirst()
            entries[oldest] = nil
            sourceBytes -= oldest.utf8.count
        }
        return segments
    }

    private func touch(_ markdown: String) {
        recency.removeAll { $0 == markdown }
        recency.append(markdown)
    }
}
