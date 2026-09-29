import XCTest
@testable import ForumIndexCore

@MainActor
final class ReaderStoreTests: XCTestCase {
    func testV2LaunchPublishesMainAndFlatSubjectsWithoutChildNavigation() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let launch = Task { await store.launch() }

        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: NavigationEnvelope(
            version: "v2",
            window: "7d",
            subjectAreas: [area("ai", count: 5), area("quiet", count: 4), area("markets", count: 6)]
        ))
        await api.waitForFeedRequests(1)
        let launchRequests = await api.recordedFeedRequests()
        XCTAssertEqual(launchRequests, [.main])
        await api.completeFeed(1, with: feed([1]))
        await launch.value

        XCTAssertEqual(store.parentDestinations.map(\.slug), ["trending", "ai", "markets"])
        XCTAssertEqual(store.childDestinations, [])
        XCTAssertEqual(store.selectedDestination?.slug, "trending")
        XCTAssertNil(store.adjacentParent(for: .previous))
        XCTAssertEqual(store.adjacentParent(for: .next)?.slug, "ai")

        let swipe = Task { await store.swipeParent(.next) }
        await api.waitForFeedRequests(2)
        let swipeRequests = await api.recordedFeedRequests()
        XCTAssertEqual(swipeRequests.last, .parent("ai"))
        await api.completeFeed(2, with: feed([2]))
        await swipe.value
        XCTAssertEqual(store.selectedDestination?.slug, "ai")
    }

    func testEligibleLaunchStartsWithForYouAndRevocationFallsBackToTrending() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await store.setForYouEligible(true)
        let launch = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: NavigationEnvelope(
            version: "v2", window: "7d", subjectAreas: [area("ai", count: 5)]
        ))
        await api.waitForFeedRequests(1)
        let requests = await api.recordedFeedRequests()
        XCTAssertEqual(requests, [.forYou])
        await api.completeFeed(1, with: feed([1]))
        await launch.value
        XCTAssertEqual(store.parentDestinations.map(\.slug), ["for_you", "trending", "ai"])
        XCTAssertEqual(store.selectedDestination, .forYou)

        let revoke = Task { await store.setForYouEligible(false) }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([2]))
        await revoke.value
        XCTAssertEqual(store.parentDestinations.map(\.slug), ["trending", "ai"])
        XCTAssertEqual(store.selectedDestination, .main)
        await store.setForYouEligible(true)
        XCTAssertEqual(store.parentDestinations.first, .forYou)
        XCTAssertEqual(store.selectedDestination, .main, "Unlocking must not interrupt the current page")
    }

    func testV2MainFeedDoesNotCollideWithBackendSubjectSlugs() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let launch = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: NavigationEnvelope(
            version: "v2",
            window: "7d",
            subjectAreas: [area("main", count: 5), area("main-feed", count: 5)]
        ))
        await api.waitForFeedRequests(1)
        await api.completeFeed(1, with: feed([1]))
        await launch.value

        XCTAssertEqual(
            store.parentDestinations.map(\.id),
            ["main-feed", "parent:main", "parent:main-feed"]
        )
        let mainSubject = store.parentDestinations[1]
        let firstSelection = Task { await store.selectDestination(mainSubject) }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([2]))
        await firstSelection.value

        let secondSelection = Task { await store.selectParent(slug: "main-feed") }
        await api.waitForFeedRequests(3)
        let requests = await api.recordedFeedRequests()
        XCTAssertEqual(requests, [.main, .parent("main"), .parent("main-feed")])
        await api.completeFeed(3, with: feed([3]))
        await secondSelection.value
        XCTAssertEqual(store.selectedDestination?.id, "parent:main-feed")
    }

    func testLaunchFiltersTaxonomySelectsFirstParentAllAndKeepsFirstPage() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let launch = Task { await store.launch() }

        await api.waitForTaxonomyRequests(1)
        XCTAssertEqual(store.taxonomyState, .initialLoading)
        await api.completeTaxonomy(1, with: taxonomy([
            area("low", count: 9),
            area("alpha", count: 10, children: [child("hidden", count: 9), child("swift", count: 10)]),
            area("beta", count: 11)
        ]))
        await api.waitForFeedRequests(1)
        let launchRequests = await api.recordedFeedRequests()
        XCTAssertEqual(launchRequests, [.parent("alpha")])
        await api.completeFeed(1, with: feed(1...125))
        await launch.value

        XCTAssertEqual(store.taxonomy?.subjectAreas.map(\.slug), ["alpha", "beta"])
        XCTAssertEqual(store.parentDestinations.map(\.slug), ["alpha", "beta"])
        XCTAssertEqual(store.childDestinations.map(\.slug), ["alpha", "swift"])
        XCTAssertEqual(store.selectedDestination, .all(parent: area("alpha", count: 10, children: [child("swift", count: 10)])))
        XCTAssertEqual(store.feedState.rows.map(\.id), Array(1...30))
        XCTAssertEqual(store.feedState.kind, .loaded)
    }

    func testEmptyQualifyingTaxonomyPublishesEmptyWithoutFeedRequest() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let launch = Task { await store.launch() }

        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: taxonomy([area("low", count: 9)]))
        await launch.value

        XCTAssertEqual(store.taxonomyState, .emptyTaxonomy)
        XCTAssertNil(store.selectedDestination)
        let requests = await api.recordedFeedRequests()
        XCTAssertEqual(requests, [])
    }

    func testTaxonomyFailureIsRetryableAndCancellationIsNotPublishedAsFailure() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let first = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.failTaxonomy(1, with: ReaderTestError.offline)
        await first.value
        XCTAssertEqual(store.taxonomyState, .failed(message: "offline"))

        let retry = Task { await store.retryTaxonomy() }
        await api.waitForTaxonomyRequests(2)
        await api.completeTaxonomy(2, with: taxonomy([area("alpha", count: 10)]))
        await api.waitForFeedRequests(1)
        await api.completeFeed(1, with: feed([1]))
        await retry.value
        XCTAssertEqual(store.taxonomyState, .loaded)

        let refresh = Task { await store.refreshTaxonomy() }
        await api.waitForTaxonomyRequests(3)
        refresh.cancel()
        await api.failTaxonomy(3, with: ReaderTestError.offline)
        await refresh.value
        XCTAssertEqual(store.taxonomyState, .loaded)
    }

    func testRetryAfterFailedTaxonomyRefreshRefetchesInsteadOfUsingCache() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")])

        let failedRefresh = Task { await store.refreshTaxonomy() }
        await api.waitForTaxonomyRequests(2)
        await api.failTaxonomy(2, with: ReaderTestError.offline)
        await failedRefresh.value
        XCTAssertEqual(store.taxonomyState, .failed(message: "offline"))

        let retry = Task { await store.retryTaxonomy() }
        await api.waitForTaxonomyRequests(3)
        await api.completeTaxonomy(3, with: taxonomy([area("alpha")]))
        await retry.value
        XCTAssertEqual(store.taxonomyState, .loaded)
    }

    func testCancelledEmptyTaxonomyRefreshRestoresEmptyState() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let launch = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: taxonomy([]))
        await launch.value
        XCTAssertEqual(store.taxonomyState, .emptyTaxonomy)

        let refresh = Task { await store.refreshTaxonomy() }
        await api.waitForTaxonomyRequests(2)
        refresh.cancel()
        await api.failTaxonomy(2, with: ReaderTestError.offline)
        await refresh.value
        XCTAssertEqual(store.taxonomyState, .emptyTaxonomy)
    }

    func testCancellingNewerOverlappingTaxonomyRefreshRestoresLastStableState() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")])

        let first = Task { await store.refreshTaxonomy() }
        await api.waitForTaxonomyRequests(2)
        let second = Task { await store.refreshTaxonomy() }
        await api.waitForTaxonomyRequests(3)

        second.cancel()
        await api.failTaxonomy(3, with: ReaderTestError.offline)
        await second.value
        await api.failTaxonomy(2, with: ReaderTestError.offline)
        await first.value

        XCTAssertEqual(store.taxonomyState, .loaded)
    }

    func testParentSwipeOnlyFromAllMovesOneStepClampsAndDirectSelectionResetsToAll() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha"), area("beta", children: [child("b1")]), area("gamma")])

        await store.swipeParent(.previous)
        XCTAssertEqual(store.selectedDestination?.slug, "alpha")
        let swipeToBeta = Task { await store.swipeParent(.next) }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([2]))
        await swipeToBeta.value
        XCTAssertEqual(store.selectedDestination?.slug, "beta")
        let selectB1 = Task { await store.selectChild(slug: "b1") }
        await api.waitForFeedRequests(3)
        await api.completeFeed(3, with: feed([3]))
        await selectB1.value
        await store.swipeParent(.next)
        XCTAssertEqual(store.selectedDestination?.slug, "b1", "Parent swipes are ignored while a child is selected")

        let selectGamma = Task { await store.selectParent(slug: "gamma") }
        await api.waitForFeedRequests(4)
        await api.completeFeed(4, with: feed([4]))
        await selectGamma.value
        XCTAssertTrue(store.selectedDestination?.isAll == true)
        XCTAssertEqual(store.selectedDestination?.parentSlug, "gamma")
        await store.swipeParent(.next)
        XCTAssertEqual(store.selectedDestination?.parentSlug, "gamma")
    }

    func testChildSwipeTraversesAllAndQualifyingSiblingsAndCallsExactEndpoints() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha", children: [child("low", count: 9), child("one"), child("two")])])

        await store.swipeChild(.previous)
        XCTAssertTrue(store.selectedDestination?.isAll == true)
        let selectOne = Task { await store.swipeChild(.next) }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([2]))
        await selectOne.value
        let selectTwo = Task { await store.swipeChild(.next) }
        await api.waitForFeedRequests(3)
        await api.completeFeed(3, with: feed([3]))
        await selectTwo.value
        await store.swipeChild(.next)

        XCTAssertEqual(store.selectedDestination?.slug, "two")
        let requests = await api.recordedFeedRequests()
        XCTAssertEqual(requests, [.parent("alpha"), .child("one"), .child("two")])
    }

    func testDestinationFeedStatesRemainAvailableIndependently() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha", children: [child("one")])], initialRows: [10])
        let alpha = store.parentDestinations[0]
        let one = store.childDestinations[1]

        let selection = Task { await store.selectDestination(one) }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([20]))
        await selection.value

        XCTAssertEqual(store.feedState(for: alpha).rows.map(\.id), [10])
        XCTAssertEqual(store.feedState(for: one).rows.map(\.id), [20])
        XCTAssertEqual(store.feedState.rows.map(\.id), [20])
    }

    func testRevisitingCachedDestinationPublishesImmediatelyWithoutRefetch() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha", children: [child("one")])], initialRows: [10])

        let selectOne = Task { await store.selectChild(slug: "one") }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([20]))
        await selectOne.value
        await store.selectParent(slug: "alpha")

        XCTAssertEqual(store.feedState.rows.map(\.id), [10])
        XCTAssertEqual(store.feedState.kind, .loaded)
        let requestCount = await api.recordedFeedRequests().count
        XCTAssertEqual(requestCount, 2)
    }

    func testStalePageRefreshCannotChangeSelection() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha", children: [child("one")])], initialRows: [10])
        let alpha = store.parentDestinations[0]
        let one = store.childDestinations[1]

        let selection = Task { await store.selectDestination(one) }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([20]))
        await selection.value

        let staleRefresh = Task { await store.refreshFeed(alpha) }
        for _ in 0..<10 { await Task.yield() }
        let requestCount = await api.recordedFeedRequests().count
        if requestCount > 2 {
            await api.completeFeed(3, with: feed([11]))
        }
        await staleRefresh.value

        XCTAssertEqual(store.selectedDestination?.id, one.id)
        XCTAssertEqual(requestCount, 2)
    }

    func testExplicitFeedRefreshRetainsRowsAndRefetchesSelectedDestination() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: [10])

        let refresh = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(2)
        XCTAssertEqual(store.feedState.kind, .refreshing)
        XCTAssertEqual(store.feedState.rows.map(\.id), [10])
        await api.completeFeed(2, with: feed([11]))
        await refresh.value

        XCTAssertEqual(store.feedState.rows.map(\.id), [11])
        let requests = await api.recordedFeedRequests()
        XCTAssertEqual(requests, [.parent("alpha"), .parent("alpha")])
    }

    func testEmptyFeedPublishesEmptyState() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: [])

        XCTAssertEqual(store.feedState, .empty)
    }

    func testRefreshingKnownEmptyFeedUsesRefreshingState() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: [])

        let refresh = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(2)
        XCTAssertEqual(store.feedState, .refreshing([]))
        await api.completeFeed(2, with: feed([]))
        await refresh.value
        XCTAssertEqual(store.feedState, .empty)
    }

    func testInitialFeedFailureIsRetryable() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let launch = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: taxonomy([area("alpha")]))
        await api.waitForFeedRequests(1)
        await api.failFeed(1, with: ReaderTestError.offline)
        await launch.value

        XCTAssertEqual(store.feedState, .failed(rows: [], message: "offline"))

        let retry = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([2]))
        await retry.value
        XCTAssertEqual(store.feedState.rows.map(\.id), [2])
        XCTAssertEqual(store.feedState.kind, .loaded)
    }

    func testRefreshFailureRetainsStaleRowsAndCancellationRestoresLoadedState() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: [10])

        let failedRefresh = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(2)
        await api.failFeed(2, with: ReaderTestError.offline)
        await failedRefresh.value
        XCTAssertEqual(store.feedState, .failed(rows: [feedTopic(10)], message: "offline"))

        let cancelledRefresh = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(3)
        cancelledRefresh.cancel()
        await api.failFeed(3, with: ReaderTestError.offline)
        await cancelledRefresh.value
        XCTAssertEqual(store.feedState.kind, .loaded)
        XCTAssertEqual(store.feedState.rows.map(\.id), [10])
    }

    func testStaleSelectionResponseCannotOverwriteNewDestination() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha", children: [child("one"), child("two")])])

        let selectOne = Task { await store.selectChild(slug: "one") }
        await api.waitForFeedRequests(2)
        let selectTwo = Task { await store.selectChild(slug: "two") }
        await api.waitForFeedRequests(3)
        await api.completeFeed(3, with: feed([200]))
        await selectTwo.value
        await api.completeFeed(2, with: feed([100]))
        await selectOne.value

        XCTAssertEqual(store.selectedDestination?.slug, "two")
        XCTAssertEqual(store.feedState.rows.map(\.id), [200])
    }

    func testNewerSameDestinationRefreshFencesOlderRefresh() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: [1])

        let first = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(2)
        let second = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(3)
        await api.completeFeed(3, with: feed([3]))
        await second.value
        await api.completeFeed(2, with: feed([2]))
        await first.value

        XCTAssertEqual(store.feedState.rows.map(\.id), [3])
    }

    func testTaxonomyRefreshPreservesSelectedChildBySlugsWithoutRefetchWhenCached() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha", children: [child("one"), child("two")])])
        let selectTwo = Task { await store.selectChild(slug: "two") }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([20]))
        await selectTwo.value

        let refresh = Task { await store.refreshTaxonomy() }
        await api.waitForTaxonomyRequests(2)
        XCTAssertEqual(store.taxonomyState, .refreshing)
        await api.completeTaxonomy(2, with: taxonomy([area("other"), area("alpha", children: [child("two"), child("three")])]))
        await refresh.value

        XCTAssertEqual(store.selectedDestination?.slug, "two")
        XCTAssertEqual(store.selectedDestination?.parentSlug, "alpha")
        XCTAssertEqual(store.childDestinations.map(\.slug), ["alpha", "two", "three"])
        let requestCount = await api.recordedFeedRequests().count
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(store.feedState.rows.map(\.id), [20])
    }

    func testTaxonomyRefreshFallsBackToFirstParentAllAndLoadsOnlyWhenNotCached() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha", children: [child("one")])])
        let selectOne = Task { await store.selectChild(slug: "one") }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([2]))
        await selectOne.value

        let refresh = Task { await store.refreshTaxonomy() }
        await api.waitForTaxonomyRequests(2)
        await api.completeTaxonomy(2, with: taxonomy([area("beta"), area("alpha")]))
        await api.waitForFeedRequests(3)
        let lastRequest = await api.recordedFeedRequests().last
        XCTAssertEqual(lastRequest, .parent("beta"))
        await api.completeFeed(3, with: feed([3]))
        await refresh.value

        XCTAssertTrue(store.selectedDestination?.isAll == true)
        XCTAssertEqual(store.selectedDestination?.parentSlug, "beta")
        XCTAssertEqual(store.feedState.rows.map(\.id), [3])
    }

    func testLoadNextPageAppendsUniqueRowsAndStopsAfterThreePages() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: Array(1...30))

        let destination = store.parentDestinations[0]
        let second = Task { await store.loadNextPage(for: destination) }
        await api.waitForFeedRequests(2)
        let duplicate = Task { await store.loadNextPage(for: destination) }
        for _ in 0..<10 { await Task.yield() }
        let inFlightRequestCount = await api.recordedFeedRequests().count
        XCTAssertEqual(inFlightRequestCount, 2)
        await api.completeFeed(2, with: feed(25...54))
        await second.value
        await duplicate.value
        XCTAssertEqual(store.feedState.rows.map(\.id), Array(1...54))

        let third = Task { await store.loadNextPage(for: destination) }
        await api.waitForFeedRequests(3)
        await api.completeFeed(3, with: feed(55...84))
        await third.value
        await store.loadNextPage(for: destination)

        XCTAssertEqual(store.feedState.rows.map(\.id), Array(1...84))
        let pages = await api.recordedFeedPages()
        let requestCount = await api.recordedFeedRequests().count
        XCTAssertEqual(pages, [1, 2, 3])
        XCTAssertEqual(requestCount, 3)
    }

    func testPreloadNextSubjectCachesItWithoutChangingSelection() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let launch = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: NavigationEnvelope(
            version: "v2",
            window: "5d",
            subjectAreas: [area("ai", count: 5), area("markets", count: 5)]
        ))
        await api.waitForFeedRequests(1)
        await api.completeFeed(1, with: feed([1]))
        await launch.value

        let preloadAI = Task { await store.preloadNextSubject() }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed([2]))
        await preloadAI.value
        XCTAssertEqual(store.selectedDestination?.slug, "trending")
        XCTAssertEqual(store.feedState(for: store.parentDestinations[1]).rows.map(\.id), [2])

        await store.selectDestination(store.parentDestinations[1])
        let requestCount = await api.recordedFeedRequests().count
        XCTAssertEqual(requestCount, 2)
        let preloadMarkets = Task { await store.preloadNextSubject() }
        await api.waitForFeedRequests(3)
        await api.completeFeed(3, with: feed([3]))
        await preloadMarkets.value
        XCTAssertEqual(store.feedState(for: store.parentDestinations[2]).rows.map(\.id), [3])
    }

    func testPreloadNextSubjectUsesVisibleOrderAndSkipsHiddenSubjects() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let launch = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: NavigationEnvelope(
            version: "v2",
            window: "5d",
            subjectAreas: [area("ai", count: 5), area("markets", count: 5)]
        ))
        await api.waitForFeedRequests(1)
        await api.completeFeed(1, with: feed([1]))
        await launch.value

        let visible = [store.parentDestinations[0], store.parentDestinations[2]]
        let preload = Task { await store.preloadNextSubject(in: visible) }
        await api.waitForFeedRequests(2)
        let requests = await api.recordedFeedRequests()
        XCTAssertEqual(requests[1], .parent("markets"))
        await api.completeFeed(2, with: feed([3]))
        await preload.value

        XCTAssertTrue(store.feedState(for: store.parentDestinations[1]).rows.isEmpty)
        XCTAssertEqual(store.feedState(for: store.parentDestinations[2]).rows.map(\.id), [3])
    }

    func testRefreshDiscardsAnOlderPaginationResponse() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: Array(1...30))
        let destination = store.parentDestinations[0]

        let pagination = Task { await store.loadNextPage(for: destination) }
        await api.waitForFeedRequests(2)
        let refresh = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(3)

        await api.completeFeed(3, with: feed([100]))
        await refresh.value
        await api.completeFeed(2, with: feed(31...60))
        await pagination.value

        XCTAssertEqual(store.feedState.rows.map(\.id), [100])
    }

    func testRefreshDiscardsAnOlderPaginationFailure() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: Array(1...30))
        let destination = store.parentDestinations[0]

        let pagination = Task { await store.loadNextPage(for: destination) }
        await api.waitForFeedRequests(2)
        let refresh = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(3)

        await api.completeFeed(3, with: feed([100]))
        await refresh.value
        await api.failFeed(2, with: ReaderTestError.offline)
        await pagination.value

        guard case let .loaded(rows) = store.feedState else {
            return XCTFail("Expected fresh feed to remain loaded")
        }
        XCTAssertEqual(rows.map(\.id), [100])
    }

    func testRefreshBlocksPaginationUntilFreshPageOneFinishes() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: Array(1...30))
        let destination = store.parentDestinations[0]

        let second = Task { await store.loadNextPage(for: destination) }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed(31...60))
        await second.value

        let refresh = Task { await store.refreshFeed() }
        await api.waitForFeedRequests(3)
        await store.loadNextPage(for: destination)
        let requestCount = await api.recordedFeedRequests().count
        XCTAssertEqual(requestCount, 3)

        await api.completeFeed(3, with: feed(101...130))
        await refresh.value
        XCTAssertEqual(store.loadedPage(for: destination), 1)
    }

    func testDuplicateOnlyPageStillTriggersThirdPage() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        await launch(store, api, areas: [area("alpha")], initialRows: Array(1...30))
        let destination = store.parentDestinations[0]

        let second = Task { await store.loadNextPage(for: destination) }
        await api.waitForFeedRequests(2)
        await api.completeFeed(2, with: feed(1...30))
        await second.value
        XCTAssertEqual(store.loadedPage(for: destination), 2)

        let third = Task { await store.loadNextPage(for: destination) }
        await api.waitForFeedRequests(3)
        await api.completeFeed(3, with: feed(31...60))
        await third.value

        XCTAssertEqual(store.feedState.rows.map(\.id), Array(1...60))
        let pages = await api.recordedFeedPages()
        XCTAssertEqual(pages, [1, 2, 3])
    }

    func testChangingSelectionCancelsThePreviousNextSubjectPreload() async {
        let api = ControlledReaderAPI()
        let store = makeStore(api)
        let launch = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: NavigationEnvelope(
            version: "v2",
            window: "5d",
            subjectAreas: [area("ai", count: 5), area("markets", count: 5)]
        ))
        await api.waitForFeedRequests(1)
        await api.completeFeed(1, with: feed([1]))
        await launch.value

        let oldPreload = Task { await store.preloadNextSubject() }
        await api.waitForFeedRequests(2)
        let selection = Task { await store.selectDestination(store.parentDestinations[1]) }
        while store.selectedDestination?.slug != "ai" { await Task.yield() }
        let currentPreload = Task { await store.preloadNextSubject() }

        await api.waitForFeedCancellations(1)
        await api.waitForFeedRequests(3)
        let requests = await api.recordedFeedRequests()
        XCTAssertEqual(requests[2], .parent("markets"))
        await api.completeFeed(3, with: feed([3]))
        await currentPreload.value
        await api.waitForFeedRequests(4)
        await api.completeFeed(4, with: feed([2]))
        await selection.value
        await oldPreload.value

        let cancellations = await api.recordedFeedCancellations()
        XCTAssertEqual(cancellations, [2])
        XCTAssertEqual(store.feedState(for: store.parentDestinations[1]).rows.map(\.id), [2])
        XCTAssertEqual(store.feedState(for: store.parentDestinations[2]).rows.map(\.id), [3])
    }

    func testLastSubjectCancelsAnObsoletePreload() async {
        let api = ControlledReaderAPI()
        await api.ignoreFeedCancellations()
        let store = makeStore(api)
        let launch = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: NavigationEnvelope(
            version: "v2",
            window: "5d",
            subjectAreas: [area("ai", count: 5), area("markets", count: 5)]
        ))
        await api.waitForFeedRequests(1)
        await api.completeFeed(1, with: feed([1]))
        await launch.value

        let obsoletePreload = Task { await store.preloadNextSubject() }
        await api.waitForFeedRequests(2)
        let selection = Task { await store.selectDestination(store.parentDestinations[2]) }
        await api.waitForFeedRequests(3)
        await store.preloadNextSubject()
        for _ in 0..<10 { await Task.yield() }

        let cancellations = await api.recordedFeedCancellations()
        XCTAssertEqual(cancellations, [2])
        await api.completeFeed(2, with: feed([2]))
        await api.completeFeed(3, with: feed([3]))
        await selection.value
        await obsoletePreload.value
        XCTAssertTrue(store.feedState(for: store.parentDestinations[1]).rows.isEmpty)
    }

    private func makeStore(_ api: ControlledReaderAPI) -> ReaderStore {
        ReaderStore(apiClient: api, taxonomyCache: LaunchTaxonomyCache(apiClient: api))
    }

    private func launch(
        _ store: ReaderStore,
        _ api: ControlledReaderAPI,
        areas: [SubjectArea],
        initialRows: [Int] = [1]
    ) async {
        let task = Task { await store.launch() }
        await api.waitForTaxonomyRequests(1)
        await api.completeTaxonomy(1, with: taxonomy(areas))
        await api.waitForFeedRequests(1)
        await api.completeFeed(1, with: feed(initialRows))
        await task.value
    }
}

private enum ReaderTestError: Error, CustomStringConvertible {
    case offline
    var description: String { "offline" }
}

private enum RecordedFeedRequest: Equatable, Sendable {
    case main
    case forYou
    case parent(String)
    case child(String)
}

private actor ControlledReaderAPI: APIClientProtocol {
    private(set) var feedRequests: [RecordedFeedRequest] = []
    private(set) var feedPages: [Int] = []
    private(set) var feedCancellations: [Int] = []
    private var ignoresFeedCancellations = false
    private var taxonomyCount = 0
    private var taxonomyContinuations: [Int: CheckedContinuation<NavigationEnvelope, any Error>] = [:]
    private var feedContinuations: [Int: CheckedContinuation<TopicFeedEnvelope, any Error>] = [:]
    private var taxonomyWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var feedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var feedCancellationWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func fetchTaxonomy() async throws -> NavigationEnvelope {
        taxonomyCount += 1
        let number = taxonomyCount
        resume(&taxonomyWaiters, through: number)
        return try await withCheckedThrowingContinuation { taxonomyContinuations[number] = $0 }
    }

    func fetchParentTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope {
        try await record(.parent(slug), page: page)
    }

    func fetchForYouTopics(page: Int) async throws -> TopicFeedEnvelope {
        try await record(.forYou, page: page)
    }

    func fetchMainTopics(page: Int) async throws -> TopicFeedEnvelope {
        try await record(.main, page: page)
    }

    func fetchChildTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope {
        try await record(.child(slug), page: page)
    }

    func waitForTaxonomyRequests(_ count: Int) async {
        guard taxonomyCount < count else { return }
        await withCheckedContinuation { taxonomyWaiters.append((count, $0)) }
    }

    func waitForFeedRequests(_ count: Int) async {
        guard feedRequests.count < count else { return }
        await withCheckedContinuation { feedWaiters.append((count, $0)) }
    }

    func waitForFeedCancellations(_ count: Int) async {
        guard feedCancellations.count < count else { return }
        await withCheckedContinuation { feedCancellationWaiters.append((count, $0)) }
    }

    func recordedFeedRequests() -> [RecordedFeedRequest] {
        feedRequests
    }

    func recordedFeedPages() -> [Int] {
        feedPages
    }

    func recordedFeedCancellations() -> [Int] {
        feedCancellations
    }

    func ignoreFeedCancellations() {
        ignoresFeedCancellations = true
    }

    func completeTaxonomy(_ number: Int, with value: NavigationEnvelope) {
        taxonomyContinuations.removeValue(forKey: number)?.resume(returning: value)
    }

    func failTaxonomy(_ number: Int, with error: any Error) {
        taxonomyContinuations.removeValue(forKey: number)?.resume(throwing: error)
    }

    func completeFeed(_ number: Int, with value: TopicFeedEnvelope) {
        feedContinuations.removeValue(forKey: number)?.resume(returning: value)
    }

    func failFeed(_ number: Int, with error: any Error) {
        feedContinuations.removeValue(forKey: number)?.resume(throwing: error)
    }

    private func record(_ request: RecordedFeedRequest, page: Int) async throws -> TopicFeedEnvelope {
        feedRequests.append(request)
        feedPages.append(page)
        let number = feedRequests.count
        resume(&feedWaiters, through: number)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { feedContinuations[number] = $0 }
        } onCancel: {
            Task { await self.cancelFeed(number) }
        }
    }

    private func cancelFeed(_ number: Int) {
        feedCancellations.append(number)
        resume(&feedCancellationWaiters, through: feedCancellations.count)
        guard !ignoresFeedCancellations,
              let continuation = feedContinuations.removeValue(forKey: number) else { return }
        continuation.resume(throwing: CancellationError())
    }

    private func resume(_ waiters: inout [(Int, CheckedContinuation<Void, Never>)], through count: Int) {
        let ready = waiters.filter { $0.0 <= count }
        waiters.removeAll { $0.0 <= count }
        ready.forEach { $0.1.resume() }
    }
}

private func taxonomy(_ areas: [SubjectArea]) -> NavigationEnvelope {
    NavigationEnvelope(window: "7d", subjectAreas: areas)
}

private func area(_ slug: String, count: Int = 10, children: [ChildSubject] = []) -> SubjectArea {
    SubjectArea(id: stableID(slug), name: slug.capitalized, slug: slug, topicCount: count, subjects: children)
}

private func child(_ slug: String, count: Int = 10) -> ChildSubject {
    ChildSubject(id: stableID(slug), name: slug.capitalized, slug: slug, topicCount: count)
}

private func stableID(_ value: String) -> Int {
    value.utf8.reduce(0) { $0 * 31 + Int($1) }
}

private func feed<S: Sequence>(_ ids: S) -> TopicFeedEnvelope where S.Element == Int {
    let topics = ids.map(feedTopic)
    return TopicFeedEnvelope(count: topics.count, results: topics)
}

private func feedTopic(_ id: Int) -> Topic {
    Topic(
        id: id,
        title: "Topic \(id)",
        url: URL(string: "https://example.com/t/\(id)"),
        excerpt: nil,
        forum: ForumSummary(id: 1, name: "Forum", slug: "forum", baseURL: URL(string: "https://example.com"))
    )
}
