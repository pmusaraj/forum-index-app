import Foundation

/// Shares short-lived initial documents, not mutable readers or bookmark resume state.
public actor TopicDocumentCache {
    public static let shared = TopicDocumentCache()

    private struct Entry {
        let document: MarkdownTopicDocument
        let expires: Date
        let bytes: Int
    }

    private struct Pending {
        let id = UUID()
        let task: Task<(MarkdownTopicDocument, Int), Error>
    }

    private let capacity: Int
    private let maximumBytes: Int
    private let lifetime: TimeInterval
    private var entries: [URL: Entry] = [:]
    private var recency: [URL] = []
    private var pending: [URL: Pending] = [:]
    private var pendingOrder: [URL] = []

    public init(capacity: Int = 12, maximumBytes: Int = 4 * 1024 * 1024, lifetime: TimeInterval = 120) {
        self.capacity = max(1, capacity)
        self.maximumBytes = max(0, maximumBytes)
        self.lifetime = lifetime
    }

    public func load(url: URL, fetch: @escaping @Sendable (URL) async throws -> String) async throws -> MarkdownTopicDocument {
        try Task.checkCancellation()
        if let entry = entries[url], entry.expires > Date() {
            touch(url)
            return entry.document
        }
        entries[url] = nil
        recency.removeAll { $0 == url }

        let request: Pending
        if let existing = pending[url] {
            request = existing
        } else {
            // Rapid paging must not leave an unbounded queue of speculative requests.
            if pending.count >= capacity, let oldest = pendingOrder.first {
                pending.removeValue(forKey: oldest)?.task.cancel()
                pendingOrder.removeFirst()
            }
            request = Pending(task: Task {
                let markdown = try await fetch(url)
                try Task.checkCancellation()
                // This task inherits the cache actor, so parsing never runs on the main actor.
                return (MarkdownTopicDocument(markdown: markdown, baseURL: url), markdown.utf8.count)
            })
            pending[url] = request
            pendingOrder.append(url)
        }
        do {
            let (document, bytes) = try await request.task.value
            if pending[url]?.id == request.id {
                pending[url] = nil
                pendingOrder.removeAll { $0 == url }
                if bytes <= maximumBytes {
                    entries[url] = Entry(document: document, expires: Date().addingTimeInterval(lifetime), bytes: bytes)
                    touch(url)
                    while entries.count > capacity || entries.values.reduce(0, { $0 + $1.bytes }) > maximumBytes {
                        entries[recency.removeFirst()] = nil
                    }
                }
            }
            // A disappearing view does not cancel another reader's shared request.
            try Task.checkCancellation()
            return document
        } catch {
            if pending[url]?.id == request.id {
                pending[url] = nil
                pendingOrder.removeAll { $0 == url }
            }
            throw error
        }
    }

    private func touch(_ url: URL) {
        recency.removeAll { $0 == url }
        recency.append(url)
    }
}
