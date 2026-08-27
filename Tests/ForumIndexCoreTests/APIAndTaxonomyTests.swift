import Foundation
import XCTest
@testable import ForumIndexCore

final class APIModelTests: XCTestCase {
    func testDecodesV2FlatSubjectTaxonomy() throws {
        let json = #"{"version":"v2","window":"7d","count":2,"subjects":[{"id":1,"name":"AI","slug":"ai","description":"Artificial intelligence","position":0,"topic_count":42},{"id":2,"name":"Markets","slug":"markets","description":"Business and economics","position":1,"topic_count":12}]}"#

        let envelope = try JSONDecoder().decode(NavigationEnvelope.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.version, "v2")
        XCTAssertEqual(envelope.subjectAreas.map(\.slug), ["ai", "markets"])
        XCTAssertTrue(envelope.subjectAreas.allSatisfy(\.subjects.isEmpty))
    }

    func testDecodesProductionShapedTaxonomyInAPIPresentedOrder() throws {
        let data = Data(Self.taxonomyJSON.utf8)
        let envelope = try JSONDecoder().decode(NavigationEnvelope.self, from: data)

        XCTAssertEqual(envelope.window, "7d")
        XCTAssertEqual(envelope.count, 2)
        XCTAssertEqual(envelope.subjectAreas.map(\.slug), ["technology", "science"])
        XCTAssertEqual(envelope.subjectAreas[0].description, "Technical fields")
        XCTAssertEqual(envelope.subjectAreas[0].position, 1)
        XCTAssertEqual(envelope.subjectAreas[0].topicCount, 42)
        XCTAssertEqual(envelope.subjectAreas[0].subjects.map(\.slug), ["swift", "rust"])
        XCTAssertEqual(envelope.subjectAreas[0].subjects[0].topicCount, 18)
    }

    func testDecodesParentAndChildFeedMetadataAndOptionalTopicFields() throws {
        let parent = try JSONDecoder().decode(TopicFeedEnvelope.self, from: Data(Self.parentFeedJSON.utf8))
        XCTAssertEqual(parent.subjectArea?.slug, "technology")
        XCTAssertNil(parent.subject)
        XCTAssertEqual(parent.count, 2)
        XCTAssertEqual(parent.results[0].forum.baseURL, URL(string: "https://forums.swift.org"))
        XCTAssertEqual(parent.results[0].url, URL(string: "https://forums.swift.org/t/1"))
        XCTAssertNil(parent.results[0].excerpt)
        XCTAssertNil(parent.results[1].url, "Empty URL strings must decode safely as nil")
        XCTAssertNil(parent.results[1].excerpt, "Empty excerpts must decode safely as nil")
        XCTAssertNil(parent.results[1].forum.baseURL)

        let child = try JSONDecoder().decode(TopicFeedEnvelope.self, from: Data(Self.childFeedJSON.utf8))
        XCTAssertNil(child.subjectArea)
        XCTAssertEqual(child.subject?.slug, "swift")
        XCTAssertEqual(child.results[0].excerpt, "<p>Hello &amp; welcome</p>")
    }

    func testTopicAndForumWebURLsDecodeWithSharedHTTPSOnlyPolicy() throws {
        let payloads = [
            (#""https://example.com/t/1""#, URL(string: "https://example.com/t/1")),
            (#""http://example.com/t/1""#, nil),
            (#""/relative/path""#, nil),
            (#""ftp://example.com/file""#, nil),
            (#""not a url""#, nil),
            ("42", nil)
        ]

        for (rawURL, expected) in payloads {
            let json = #"{"count":1,"results":[{"id":1,"title":"Topic","url":\#(rawURL),"forum":{"id":2,"name":"Forum","slug":"forum","base_url":\#(rawURL)}}]}"#
            let feed = try JSONDecoder().decode(TopicFeedEnvelope.self, from: Data(json.utf8))
            XCTAssertEqual(feed.results[0].url, expected, "Unexpected topic URL policy for \(rawURL)")
            XCTAssertEqual(feed.results[0].forum.baseURL, expected, "Unexpected forum URL policy for \(rawURL)")
        }
    }

    func testDecodesReplyCountAndPublishedDate() throws {
        let json = #"{"count":1,"results":[{"id":1,"title":"Topic","url":"https://example.com/t/1","published_at":"2026-08-26T10:19:02.655Z","engagement":{"replies":12},"forum":{"id":2,"name":"Forum","slug":"forum","base_url":"https://example.com"}}]}"#
        let feed = try JSONDecoder().decode(TopicFeedEnvelope.self, from: Data(json.utf8))
        let topic = try XCTUnwrap(feed.results.first)
        let expectedFormatter = ISO8601DateFormatter()
        expectedFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = try XCTUnwrap(expectedFormatter.date(from: "2026-08-26T10:19:02.655Z"))

        XCTAssertEqual(topic.replyCount, 12)
        XCTAssertEqual(topic.publishedAt, expectedDate)
    }

    func testTaxonomyDefaultsMissingAndNullOptionalPresentationFields() throws {
        let envelope = try JSONDecoder().decode(
            NavigationEnvelope.self,
            from: Data(Self.sparseTaxonomyJSON.utf8)
        )

        XCTAssertEqual(envelope.subjectAreas[0].description, "")
        XCTAssertEqual(envelope.subjectAreas[0].position, 0)
        XCTAssertEqual(envelope.subjectAreas[0].subjects, [])
        XCTAssertEqual(envelope.subjectAreas[1].description, "")
        XCTAssertEqual(envelope.subjectAreas[1].position, 0)
        XCTAssertEqual(envelope.subjectAreas[1].subjects[0].description, "")
        XCTAssertEqual(envelope.subjectAreas[1].subjects[0].position, 0)
        XCTAssertEqual(envelope.subjectAreas[1].subjects[1].description, "")
        XCTAssertEqual(envelope.subjectAreas[1].subjects[1].position, 0)
    }

    func testTaxonomyStillRequiresIdentityAndTopicCountFields() {
        let missingAreaID = #"{"window":"7d","count":1,"areas":[{"name":"Area","slug":"area","topic_count":1}]}"#
        let missingChildCount = #"{"window":"7d","count":1,"areas":[{"id":1,"name":"Area","slug":"area","topic_count":1,"subjects":[{"id":2,"name":"Child","slug":"child"}]}]}"#

        XCTAssertThrowsError(try JSONDecoder().decode(NavigationEnvelope.self, from: Data(missingAreaID.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(NavigationEnvelope.self, from: Data(missingChildCount.utf8)))
    }

    static let taxonomyJSON = #"""
    {
      "window": "7d",
      "count": 2,
      "areas": [
        {"id": 1, "name": "Technology", "slug": "technology", "description": "Technical fields", "position": 1, "topic_count": 42,
         "subjects": [
           {"id": 11, "name": "Swift", "slug": "swift", "description": "Swift language", "position": 1, "topic_count": 18},
           {"id": 12, "name": "Rust", "slug": "rust", "description": "Rust language", "position": 2, "topic_count": 9}
         ]},
        {"id": 2, "name": "Science", "slug": "science", "description": "Scientific fields", "position": 2, "topic_count": 8, "subjects": []}
      ]
    }
    """#

    static let sparseTaxonomyJSON = #"""
    {
      "window": "7d",
      "count": 2,
      "areas": [
        {"id": 1, "name": "Missing optionals", "slug": "missing", "topic_count": 12},
        {"id": 2, "name": "Null optionals", "slug": "null", "description": null, "position": null, "topic_count": 11,
         "subjects": [
           {"id": 21, "name": "Missing child optionals", "slug": "missing-child", "topic_count": 10},
           {"id": 22, "name": "Null child optionals", "slug": "null-child", "description": null, "position": null, "topic_count": 9}
         ]}
      ]
    }
    """#

    static let parentFeedJSON = #"""
    {
      "subject_area": {"id": 1, "name": "Technology", "slug": "technology"},
      "count": 2,
      "results": [
        {"id": 101, "title": "A topic", "url": "https://forums.swift.org/t/1", "excerpt": null,
         "forum": {"id": 7, "name": "Swift Forums", "slug": "swift-forums", "base_url": "https://forums.swift.org"}},
        {"id": 102, "title": "Another", "url": "", "excerpt": "",
         "forum": {"id": 8, "name": "Example", "slug": "example", "base_url": ""}}
      ]
    }
    """#

    static let childFeedJSON = #"""
    {"subject": {"id": 11, "name": "Swift", "slug": "swift"}, "count": 1, "results": [
      {"id": 103, "title": "Child topic", "url": "https://example.com/t/103", "excerpt": "<p>Hello &amp; welcome</p>",
       "forum": {"id": 9, "name": "Example", "slug": "example", "base_url": "https://example.com"}}
    ]}
    """#
}

final class URLSessionForumIndexAPIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    func testTaxonomyRequestUsesV2FlatSubjectsEndpoint() async throws {
        MockURLProtocol.enqueue(status: 200, body: #"{"version":"v2","window":"7d","count":0,"subjects":[]}"#)
        let client = makeClient()

        _ = try await client.fetchTaxonomy()

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v2/subjects")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "window", value: "7d")])
    }

    func testSubjectRequestPercentEncodesSlugAndUsesV2TrendingThirtyCap() async throws {
        MockURLProtocol.enqueue(status: 200, body: APIModelTests.childFeedJSON)
        let client = makeClient()

        _ = try await client.fetchParentTopics(slug: "swift language")

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.percentEncodedPath,
                       "/api/v2/subjects/swift%20language/topics")
        XCTAssertEqual(queryDictionary(request), ["feed": "trending", "limit": "30"])
    }

    func testMainRequestUsesV2MainFeedAndThirtyCap() async throws {
        MockURLProtocol.enqueue(status: 200, body: APIModelTests.parentFeedJSON)
        let client = makeClient()

        _ = try await client.fetchParentTopics(slug: "main")

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v2/topics")
        XCTAssertEqual(queryDictionary(request), ["feed": "main", "limit": "30"])
    }

    func testBasePathJoiningUsesExactlyOneSlashBeforeAPIPath() async throws {
        for base in ["https://example.com", "https://example.com/root", "https://example.com/root/"] {
            MockURLProtocol.reset()
            MockURLProtocol.enqueue(status: 200, body: APIModelTests.taxonomyJSON)
            let client = URLSessionForumIndexAPIClient(session: makeSession(), baseURL: URL(string: base)!)

            _ = try await client.fetchTaxonomy()

            let request = try XCTUnwrap(MockURLProtocol.requests.first)
            let expectedPath = base.contains("/root") ? "/root/api/v2/subjects" : "/api/v2/subjects"
            XCTAssertEqual(request.url?.absoluteString, "https://example.com\(expectedPath)?window=7d",
                           "Unexpected joined URL for \(base)")
        }
    }

    func testRejectsInvalidBaseURLAndPathInjectionWithoutSendingRequest() async {
        let invalidBase = URLSessionForumIndexAPIClient(session: makeSession(), baseURL: URL(string: "file:///tmp")!)
        await assertAPIError(.invalidBaseURL) { try await invalidBase.fetchTaxonomy() }

        let client = makeClient()
        for slug in ["", " ", "\t\n", ".", "..", "a/b", "a\\b", "a%2Fb", "a?b", "a#b"] {
            await assertAPIError(.invalidSlug) { try await client.fetchParentTopics(slug: slug) }
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testSlugWithInternalSpacesRemainsSupported() async throws {
        MockURLProtocol.enqueue(status: 200, body: APIModelTests.parentFeedJSON)
        let client = makeClient()

        _ = try await client.fetchParentTopics(slug: "swift language")

        let requestURL = try XCTUnwrap(MockURLProtocol.requests.first?.url)
        XCTAssertEqual(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.percentEncodedPath,
                       "/api/v2/subjects/swift%20language/topics")
    }

    func testMapsHTTPTransportAndDecodeFailuresToTypedErrors() async {
        let client = makeClient()
        MockURLProtocol.enqueue(status: 503, body: "{}")
        await assertAPIError(.httpStatus(503)) { try await client.fetchTaxonomy() }

        MockURLProtocol.enqueue(error: URLError(.notConnectedToInternet))
        do {
            _ = try await client.fetchTaxonomy()
            XCTFail("Expected transport error")
        } catch let error as ForumIndexAPIError {
            guard case .transport = error else { return XCTFail("Unexpected error: \(error)") }
        } catch { XCTFail("Unexpected error: \(error)") }

        MockURLProtocol.enqueue(status: 200, body: "{not-json")
        do {
            _ = try await client.fetchTaxonomy()
            XCTFail("Expected decoding error")
        } catch let error as ForumIndexAPIError {
            guard case .decoding = error else { return XCTFail("Unexpected error: \(error)") }
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCancellationRemainsCancellation() async {
        MockURLProtocol.enqueue(error: URLError(.cancelled))
        let client = makeClient()
        let task = Task { try await client.fetchTaxonomy() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Cancellation was remapped: \(error)")
        }
    }

    private func makeClient() -> URLSessionForumIndexAPIClient {
        URLSessionForumIndexAPIClient(session: makeSession(), baseURL: URL(string: "https://do3.musaraj.com")!)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func queryDictionary(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
    }

    private func assertAPIError<T>(_ expected: ForumIndexAPIError, operation: () async throws -> T) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as ForumIndexAPIError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class TaxonomyCacheTests: XCTestCase {
    func testFirstLoadFetchesAndSubsequentLoadReusesMemoryCache() async throws {
        let api = StubAPIClient(taxonomies: [Self.taxonomy(topicCount: 20)])
        let cache = LaunchTaxonomyCache(apiClient: api)

        let first = try await cache.load()
        let second = try await cache.load()

        XCTAssertEqual(first, second)
        let fetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(fetchCount, 1)
    }

    func testRefreshRefetchesAndReplacesCache() async throws {
        let api = StubAPIClient(taxonomies: [Self.taxonomy(topicCount: 20), Self.taxonomy(topicCount: 30)])
        let cache = LaunchTaxonomyCache(apiClient: api)

        let initial = try await cache.load()
        let refreshed = try await cache.refresh()
        let reused = try await cache.load()
        let fetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(initial.subjectAreas[0].topicCount, 20)
        XCTAssertEqual(refreshed.subjectAreas[0].topicCount, 30)
        XCTAssertEqual(reused.subjectAreas[0].topicCount, 30)
        XCTAssertEqual(fetchCount, 2)
    }

    func testConcurrentFirstLoadsCoalesce() async throws {
        let api = StubAPIClient()
        let probe = CoalescingProbe()
        let cache = LaunchTaxonomyCache(apiClient: api) {
            await probe.recordJoin()
        }

        let one = Task { try await cache.load() }
        let two = Task { try await cache.load() }

        await api.waitForTaxonomyFetchCount(1)
        await probe.waitForJoin()
        let blockedFetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(blockedFetchCount, 1, "The acknowledged second load must share the blocked first fetch")

        let expected = Self.taxonomy(topicCount: 20)
        await api.completeTaxonomyFetch(1, with: expected)
        let values = try await (one.value, two.value)

        XCTAssertEqual(values.0, expected)
        XCTAssertEqual(values.1, expected)
        let finalFetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(finalFetchCount, 1)
    }

    func testRefreshSupersedesBlockedInitialLoadAndFencesItsCompletion() async throws {
        let api = StubAPIClient()
        let cache = LaunchTaxonomyCache(apiClient: api)
        let oldTaxonomy = Self.taxonomy(topicCount: 20)
        let refreshedTaxonomy = Self.taxonomy(topicCount: 30)

        let initialLoad = Task { try await cache.load() }
        await api.waitForTaxonomyFetchCount(1)

        let refresh = Task { try await cache.refresh() }
        await api.waitForTaxonomyFetchCount(2)
        let blockedFetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(blockedFetchCount, 2)

        await api.completeTaxonomyFetch(2, with: refreshedTaxonomy)
        let refreshValue = try await refresh.value
        XCTAssertEqual(refreshValue, refreshedTaxonomy)

        await api.completeTaxonomyFetch(1, with: oldTaxonomy)
        let initialValue = try await initialLoad.value
        let cachedValue = try await cache.load()
        let finalFetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(initialValue, oldTaxonomy)
        XCTAssertEqual(cachedValue, refreshedTaxonomy)
        XCTAssertEqual(finalFetchCount, 2)
    }

    func testClearCancelsAndFencesBlockedRequestThenNextLoadStartsNewFetch() async throws {
        let api = StubAPIClient()
        let completionProbe = CompletionProbe()
        let cache = LaunchTaxonomyCache(
            apiClient: api,
            onCoalescedLoad: {},
            onRequestCompletion: { await completionProbe.record($0) }
        )
        let oldTaxonomy = Self.taxonomy(topicCount: 20)
        let newTaxonomy = Self.taxonomy(topicCount: 40)

        let oldLoad = Task { try await cache.load() }
        await api.waitForTaxonomyFetchCount(1)
        await cache.clear()

        await assertCancellation(of: oldLoad)
        let newLoad = Task { try await cache.load() }
        await api.waitForTaxonomyFetchCount(2)

        await api.completeTaxonomyFetch(1, with: oldTaxonomy)
        await completionProbe.wait(for: 1)

        await api.completeTaxonomyFetch(2, with: newTaxonomy)
        let newValue = try await newLoad.value
        let cachedValue = try await cache.load()
        let fetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(newValue, newTaxonomy)
        XCTAssertEqual(cachedValue, newTaxonomy)
        XCTAssertEqual(fetchCount, 2)
    }

    func testAlreadyCancelledLoadsThrowBeforeCacheOrFetch() async throws {
        let api = StubAPIClient(taxonomies: [Self.taxonomy(topicCount: 20)])
        let cache = LaunchTaxonomyCache(apiClient: api)
        let cached = try await cache.load()
        let gate = AsyncGate()
        let cachedLoad = Task {
            await gate.wait()
            return try await cache.load()
        }
        cachedLoad.cancel()
        await gate.open()

        await assertCancellation(of: cachedLoad)
        let cachedFetchCount = await api.taxonomyFetchCount
        let cachedAgain = try await cache.load()
        XCTAssertEqual(cachedFetchCount, 1)
        XCTAssertEqual(cachedAgain, cached)

        let emptyAPI = StubAPIClient(taxonomies: [Self.taxonomy(topicCount: 30)])
        let emptyCache = LaunchTaxonomyCache(apiClient: emptyAPI)
        let preflightGate = AsyncGate()
        let preflightLoad = Task {
            await preflightGate.wait()
            return try await emptyCache.load()
        }
        preflightLoad.cancel()
        await preflightGate.open()

        await assertCancellation(of: preflightLoad)
        let emptyFetchCount = await emptyAPI.taxonomyFetchCount
        XCTAssertEqual(emptyFetchCount, 0)
    }

    func testCancelledCoalescedWaiterReturnsPromptlyWithoutCancellingSharedFetch() async throws {
        let api = StubAPIClient()
        let probe = CoalescingProbe()
        let cache = LaunchTaxonomyCache(apiClient: api) { await probe.recordJoin() }
        let successfulWaiter = Task { try await cache.load() }
        await api.waitForTaxonomyFetchCount(1)
        let cancelledWaiter = Task { try await cache.load() }
        await probe.waitForJoin()

        cancelledWaiter.cancel()
        await assertCancellation(of: cancelledWaiter)
        let blockedFetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(blockedFetchCount, 1)

        let expected = Self.taxonomy(topicCount: 20)
        await api.completeTaxonomyFetch(1, with: expected)
        let successfulValue = try await successfulWaiter.value
        let finalFetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(successfulValue, expected)
        XCTAssertEqual(finalFetchCount, 1)
    }

    func testCancelledRefreshWaiterDoesNotCancelCoalescedLoad() async throws {
        let api = StubAPIClient()
        let probe = CoalescingProbe()
        let cache = LaunchTaxonomyCache(apiClient: api) { await probe.recordJoin() }
        let refresh = Task { try await cache.refresh() }
        await api.waitForTaxonomyFetchCount(1)
        let load = Task { try await cache.load() }
        await probe.waitForJoin()

        refresh.cancel()
        await assertCancellation(of: refresh)

        let expected = Self.taxonomy(topicCount: 25)
        await api.completeTaxonomyFetch(1, with: expected)
        let loadValue = try await load.value
        let fetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(loadValue, expected)
        XCTAssertEqual(fetchCount, 1)
    }

    func testFailedRefreshKeepsLastGoodCacheAndLoadCanUseItWhileRefreshIsBlocked() async throws {
        let api = StubAPIClient()
        let cache = LaunchTaxonomyCache(apiClient: api)
        let initial = Self.taxonomy(topicCount: 20)
        let firstLoad = Task { try await cache.load() }
        await api.waitForTaxonomyFetchCount(1)
        await api.completeTaxonomyFetch(1, with: initial)
        let firstValue = try await firstLoad.value
        XCTAssertEqual(firstValue, initial)

        let refresh = Task { try await cache.refresh() }
        await api.waitForTaxonomyFetchCount(2)
        let duringRefresh = try await cache.load()
        XCTAssertEqual(duringRefresh, initial, "Normal loads should use stale-good cache during refresh")

        await api.failTaxonomyFetch(2, with: TestFailure.refreshFailed)
        do {
            _ = try await refresh.value
            XCTFail("Expected refresh failure")
        } catch TestFailure.refreshFailed {
        } catch {
            XCTFail("Unexpected refresh error: \(error)")
        }
        let afterFailure = try await cache.load()
        let fetchCount = await api.taxonomyFetchCount
        XCTAssertEqual(afterFailure, initial)
        XCTAssertEqual(fetchCount, 2)
    }

    func testLaunchFilteringKeepsOnlyCountsAtLeastTenAndPreservesOrder() {
        let envelope = NavigationEnvelope(window: "7d", subjectAreas: [
            SubjectArea(id: 1, name: "First", slug: "first", topicCount: 10, subjects: [
                ChildSubject(id: 11, name: "Low", slug: "low", topicCount: 9),
                ChildSubject(id: 12, name: "Keep A", slug: "a", topicCount: 10),
                ChildSubject(id: 13, name: "Keep B", slug: "b", topicCount: 11)
            ]),
            SubjectArea(id: 2, name: "Drop", slug: "drop", topicCount: 9, subjects: [
                ChildSubject(id: 21, name: "Would Keep", slug: "keep", topicCount: 99)
            ]),
            SubjectArea(id: 3, name: "Last", slug: "last", topicCount: 12, subjects: [])
        ])

        let filtered = TaxonomyFilter.launchEligible(envelope)

        XCTAssertEqual(filtered.subjectAreas.map(\.slug), ["first", "last"])
        XCTAssertEqual(filtered.subjectAreas[0].subjects.map(\.slug), ["a", "b"])
    }

    func testExcerptNormalizationDecodesEntitiesStripsTagsAndCollapsesWhitespace() {
        XCTAssertEqual(
            ExcerptNormalizer.plainText("<p>Hello&nbsp; <strong>Swift</strong></p><br>Fish &amp; Chips &#33; &#x1F44B;"),
            "Hello Swift Fish & Chips ! 👋"
        )
        XCTAssertNil(ExcerptNormalizer.plainText(nil))
        XCTAssertNil(ExcerptNormalizer.plainText("  <br>  "))
    }

    private static func taxonomy(topicCount: Int) -> NavigationEnvelope {
        NavigationEnvelope(window: "7d", subjectAreas: [
            SubjectArea(id: 1, name: "Technology", slug: "technology", topicCount: topicCount, subjects: [])
        ])
    }

    private func assertCancellation(
        of task: Task<NavigationEnvelope, any Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("Expected cancellation", file: file, line: line)
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private enum TestFailure: Error {
    case refreshFailed
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor CoalescingProbe {
    private var joined = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recordJoin() {
        joined = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func waitForJoin() async {
        guard !joined else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor CompletionProbe {
    private var completions: Set<UInt64> = []
    private var waiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]

    func record(_ generation: UInt64) {
        completions.insert(generation)
        waiters.removeValue(forKey: generation)?.forEach { $0.resume() }
    }

    func wait(for generation: UInt64) async {
        guard !completions.contains(generation) else { return }
        await withCheckedContinuation { waiters[generation, default: []].append($0) }
    }
}

private actor StubAPIClient: APIClientProtocol {
    private var taxonomies: [NavigationEnvelope]
    private(set) var taxonomyFetchCount = 0
    private var fetchContinuations: [Int: CheckedContinuation<NavigationEnvelope, any Error>] = [:]
    private var countWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private let usesControlledFetches: Bool

    init(taxonomies: [NavigationEnvelope]) {
        self.taxonomies = taxonomies
        usesControlledFetches = false
    }

    init() {
        taxonomies = []
        usesControlledFetches = true
    }

    func fetchTaxonomy() async throws -> NavigationEnvelope {
        taxonomyFetchCount += 1
        let fetchNumber = taxonomyFetchCount
        let readyWaiters = countWaiters.filter { $0.count <= fetchNumber }
        countWaiters.removeAll { $0.count <= fetchNumber }
        readyWaiters.forEach { $0.continuation.resume() }

        if usesControlledFetches {
            return try await withCheckedThrowingContinuation { continuation in
                fetchContinuations[fetchNumber] = continuation
            }
        }
        return taxonomies.removeFirst()
    }

    func waitForTaxonomyFetchCount(_ count: Int) async {
        guard taxonomyFetchCount < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    func completeTaxonomyFetch(_ fetchNumber: Int, with taxonomy: NavigationEnvelope) {
        guard let continuation = fetchContinuations.removeValue(forKey: fetchNumber) else {
            XCTFail("Taxonomy fetch \(fetchNumber) is not awaiting completion")
            return
        }
        continuation.resume(returning: taxonomy)
    }

    func failTaxonomyFetch(_ fetchNumber: Int, with error: any Error) {
        guard let continuation = fetchContinuations.removeValue(forKey: fetchNumber) else {
            XCTFail("Taxonomy fetch \(fetchNumber) is not awaiting completion")
            return
        }
        continuation.resume(throwing: error)
    }

    func fetchParentTopics(slug: String) async throws -> TopicFeedEnvelope { fatalError("Unused") }
    func fetchChildTopics(slug: String) async throws -> TopicFeedEnvelope { fatalError("Unused") }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Response {
        let status: Int?
        let body: Data?
        let error: Error?
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var responses: [Response] = []
    private nonisolated(unsafe) static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    static func reset() {
        lock.withLock {
            responses = []
            recordedRequests = []
        }
    }

    static func enqueue(status: Int, body: String) {
        lock.withLock { responses.append(Response(status: status, body: Data(body.utf8), error: nil)) }
    }

    static func enqueue(error: Error) {
        lock.withLock { responses.append(Response(status: nil, body: nil, error: error)) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response: Response? = Self.lock.withLock {
            Self.recordedRequests.append(request)
            return Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        }
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status!, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if let body = response.body { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
