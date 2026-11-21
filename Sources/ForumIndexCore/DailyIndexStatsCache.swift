import Foundation

@MainActor
public final class DailyIndexStatsCache {
    private let client: any IndexStatsAPIClientProtocol
    private let defaults: UserDefaults
    private let lastAttemptKey = "index-stats-last-attempt-v1"
    private let snapshotKey = "index-stats-snapshot-v1"
    private var refresh: Task<IndexStats?, Never>?

    public init(client: any IndexStatsAPIClientProtocol, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    public func load(now: Date = .now) async -> IndexStats? {
        if let refresh { return await refresh.value }
        let cached = defaults.data(forKey: snapshotKey).flatMap { try? JSONDecoder().decode(IndexStats.self, from: $0) }
        if let lastAttempt = defaults.object(forKey: lastAttemptKey) as? Date,
           now.timeIntervalSince(lastAttempt) < 24 * 60 * 60 {
            return cached
        }

        // Reserve the interval before starting I/O, even if the app quits or the request fails.
        defaults.set(now, forKey: lastAttemptKey)
        let task = Task { () -> IndexStats? in
            defer { refresh = nil }
            guard let fresh = try? await client.fetchIndexStats() else { return cached }
            if let data = try? JSONEncoder().encode(fresh) { defaults.set(data, forKey: snapshotKey) }
            return fresh
        }
        refresh = task
        return await task.value
    }
}
