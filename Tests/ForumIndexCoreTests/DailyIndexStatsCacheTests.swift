import XCTest
@testable import ForumIndexCore

final class DailyIndexStatsCacheTests: XCTestCase {
    @MainActor
    func testSharesRequestsAndPersistsBudgetAndSnapshotAcrossLaunches() async {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = CountingStatsClient()
        let cache = DailyIndexStatsCache(client: client, defaults: defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        async let first = cache.load(now: start)
        async let second = cache.load(now: start)
        let (a, b) = await (first, second)
        XCTAssertEqual(a?.forumsIndexed, 1)
        XCTAssertEqual(a, b)

        let reopened = DailyIndexStatsCache(client: client, defaults: UserDefaults(suiteName: suite)!)
        let withinDay = await reopened.load(now: start.addingTimeInterval(86_399))
        XCTAssertEqual(withinDay, a)
        let nextDay = await reopened.load(now: start.addingTimeInterval(86_400)) // second request fails
        XCTAssertEqual(nextDay, a)
        let afterFailure = await cache.load(now: start.addingTimeInterval(86_401))
        XCTAssertEqual(afterFailure, a)
        let fresh = await cache.load(now: start.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(fresh?.forumsIndexed, 3)
        let count = await client.calls
        XCTAssertEqual(count, 3)
    }
}

private actor CountingStatsClient: IndexStatsAPIClientProtocol {
    var calls = 0
    func fetchIndexStats() async throws -> IndexStats {
        calls += 1
        if calls == 2 { throw URLError(.notConnectedToInternet) }
        return IndexStats(forumsIndexed: calls, newTopics7d: 2, topicsCrawled7d: 3, activeUsers7d: 4)
    }
}
