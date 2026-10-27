import Foundation
import Observation

public protocol TaxonomyCacheProtocol: Sendable {
    func load() async throws -> NavigationEnvelope
    func refresh() async throws -> NavigationEnvelope
}

extension LaunchTaxonomyCache: TaxonomyCacheProtocol {}

public enum ReaderDestination: Hashable, Identifiable, Sendable {
    case main
    case discovered(DiscoveredFeed)
    case forYou
    case all(parent: SubjectArea)
    case child(parent: SubjectArea, subject: ChildSubject)

    public var id: String {
        switch self {
        case let .discovered(feed): "feed:\(feed.id)"
        case .forYou: "for-you-feed"
        case .main:
            "main-feed"
        case let .all(parent):
            "parent:\(parent.slug)"
        case let .child(parent, subject):
            "child:\(parent.slug)/\(subject.slug)"
        }
    }

    public var slug: String {
        switch self {
        case let .discovered(feed): feed.id
        case .forYou: "for_you"
        case .main: "trending"
        case let .all(parent): parent.slug
        case let .child(_, subject): subject.slug
        }
    }

    public var parentSlug: String? {
        switch self {
        case .main, .forYou, .discovered: nil
        case let .all(parent), let .child(parent, _): parent.slug
        }
    }

    public var parentName: String {
        switch self {
        case let .discovered(feed): feed.name
        case .forYou: "For You"
        case .main: "Trending"
        case let .all(parent), let .child(parent, _): parent.name
        }
    }

    public var label: String {
        switch self {
        case let .discovered(feed): feed.name
        case .forYou: "For You"
        case .main: "Trending"
        case let .all(parent): "All \(parent.name)"
        case let .child(_, subject): subject.name
        }
    }

    public var isAll: Bool {
        switch self {
        case .main, .forYou, .discovered, .all: true
        case .child: false
        }
    }

    public var isDiscovered: Bool {
        if case .discovered = self { true } else { false }
    }

    public var isSecondary: Bool {
        if case let .all(parent) = self { parent.secondary } else { false }
    }

    public static func == (lhs: ReaderDestination, rhs: ReaderDestination) -> Bool {
        switch (lhs, rhs) {
        case let (.discovered(left), .discovered(right)):
            left.id == right.id
        case (.main, .main), (.forYou, .forYou):
            true
        case let (.all(left), .all(right)):
            left.slug == right.slug
        case let (.child(leftParent, leftSubject), .child(rightParent, rightSubject)):
            leftParent.slug == rightParent.slug && leftSubject.slug == rightSubject.slug
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .discovered(feed):
            hasher.combine(4)
            hasher.combine(feed.id)
        case .forYou:
            hasher.combine(3)
        case .main:
            hasher.combine(0)
        case let .all(parent):
            hasher.combine(1)
            hasher.combine(parent.slug)
        case let .child(parent, subject):
            hasher.combine(2)
            hasher.combine(parent.slug)
            hasher.combine(subject.slug)
        }
    }
}

public enum ReaderNavigationDirection: Sendable {
    case previous
    case next
}

public enum TaxonomyLoadState: Equatable, Sendable {
    case initialLoading
    case loaded
    case refreshing
    case emptyTaxonomy
    case failed(message: String)
}

public enum FeedLoadKind: Equatable, Sendable {
    case initialLoading
    case loaded
    case refreshing
    case empty
    case failed
}

public enum FeedLoadState: Equatable, Sendable {
    case initialLoading
    case loaded([Topic])
    case refreshing([Topic])
    case empty
    case failed(rows: [Topic], message: String)

    public var rows: [Topic] {
        switch self {
        case .initialLoading, .empty: []
        case let .loaded(rows), let .refreshing(rows), let .failed(rows, _): rows
        }
    }

    public var kind: FeedLoadKind {
        switch self {
        case .initialLoading: .initialLoading
        case .loaded: .loaded
        case .refreshing: .refreshing
        case .empty: .empty
        case .failed: .failed
        }
    }
}

@MainActor
@Observable
public final class ReaderStore {
    private static let pageSize = 30
    private static let maximumPage = 3

    private struct Preload {
        let id = UUID()
        let task: Task<TopicFeedEnvelope?, Never>
    }

    public private(set) var taxonomyState: TaxonomyLoadState = .initialLoading
    public private(set) var taxonomy: NavigationEnvelope?
    public private(set) var parentDestinations: [ReaderDestination] = []
    public private(set) var childDestinations: [ReaderDestination] = []
    public private(set) var selectedDestination: ReaderDestination?
    private var feedStates: [ReaderDestination: FeedLoadState] = [:]
    private var unselectedFeedState: FeedLoadState = .initialLoading

    public var feedState: FeedLoadState {
        selectedDestination.map(feedState(for:)) ?? unselectedFeedState
    }

    private let apiClient: any APIClientProtocol
    private let taxonomyCache: any TaxonomyCacheProtocol
    private var feedCache: [ReaderDestination: [Topic]] = [:]
    private var loadedPages: [ReaderDestination: Int] = [:]
    private var destinationsWithMorePages: Set<ReaderDestination> = []
    private var pagingDestinations: Set<ReaderDestination> = []
    private var preloadTasks: [ReaderDestination: Preload] = [:]
    private var taxonomyTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var taxonomyGeneration: UInt64 = 0
    private var feedGeneration: UInt64 = 0

    public init(apiClient: any APIClientProtocol, taxonomyCache: any TaxonomyCacheProtocol) {
        self.apiClient = apiClient
        self.taxonomyCache = taxonomyCache
    }

    private var discoveredFeeds: [ReaderDestination] = []
    private var catalogGeneration: UInt64 = 0

    public func launch() async {
        async let discovery: Void = refreshFeedCatalog()
        await loadTaxonomy(refresh: false, initial: true)
        await discovery
    }

    public func refreshFeedCatalog() async {
        catalogGeneration &+= 1
        let generation = catalogGeneration
        // Discovery is optional: retain existing navigation when it is unavailable.
        guard let catalog = try? await apiClient.fetchFeeds(), !Task.isCancelled,
              catalogGeneration == generation, catalog.version == "v2" else { return }
        var seen = Set(["trending", "for_you", "main"])
        discoveredFeeds = catalog.feeds.filter { seen.insert($0.id).inserted }.map { .discovered($0) }
        guard taxonomy?.version == "v2" else { return }
        parentDestinations.removeAll { $0.isDiscovered }
        parentDestinations += discoveredFeeds
        if let selectedDestination, selectedDestination.isDiscovered,
           !parentDestinations.contains(selectedDestination) {
            await select(.main)
        }
    }

    public func retryTaxonomy() async {
        let hasPriorTaxonomy = taxonomy != nil
        await loadTaxonomy(refresh: hasPriorTaxonomy, initial: !hasPriorTaxonomy)
    }

    public func refreshTaxonomy() async {
        async let discovery: Void = refreshFeedCatalog()
        await loadTaxonomy(refresh: true, initial: false)
        await discovery
    }

    public func selectParent(slug: String) async {
        guard let destination = parentDestinations.first(where: {
            if case let .all(parent) = $0 { return parent.slug == slug }
            return false
        }) else { return }
        await select(destination)
    }

    public func selectChild(slug: String) async {
        guard let destination = childDestinations.first(where: { !$0.isAll && $0.slug == slug }) else { return }
        await select(destination)
    }

    public func selectDestination(_ destination: ReaderDestination) async {
        guard let current = (parentDestinations + childDestinations).first(where: { $0.id == destination.id }) else { return }
        await select(current)
    }

    public func swipeParent(_ direction: ReaderNavigationDirection) async {
        guard selectedDestination?.isAll == true,
              let selectedDestination,
              let index = parentDestinations.firstIndex(where: { $0.id == selectedDestination.id }) else { return }
        let target = clampedIndex(from: index, direction: direction, count: parentDestinations.count)
        guard target != index else { return }
        await select(parentDestinations[target])
    }

    public func canSwipeParent(_ direction: ReaderNavigationDirection) -> Bool {
        adjacentParent(for: direction) != nil
    }

    public func adjacentParent(for direction: ReaderNavigationDirection) -> ReaderDestination? {
        guard selectedDestination?.isAll == true,
              let selectedDestination,
              let index = parentDestinations.firstIndex(where: { $0.id == selectedDestination.id }) else { return nil }
        let target = clampedIndex(from: index, direction: direction, count: parentDestinations.count)
        return target == index ? nil : parentDestinations[target]
    }

    public func swipeChild(_ direction: ReaderNavigationDirection) async {
        guard let selectedDestination,
              let index = childDestinations.firstIndex(where: { $0.id == selectedDestination.id }) else { return }
        let target = clampedIndex(from: index, direction: direction, count: childDestinations.count)
        guard target != index else { return }
        await select(childDestinations[target])
    }

    public func refreshFeed() async {
        guard let selectedDestination else { return }
        await select(selectedDestination, forceRefresh: true)
    }

    public func refreshFeed(_ destination: ReaderDestination) async {
        guard selectedDestination?.id == destination.id,
              let current = (parentDestinations + childDestinations).first(where: { $0.id == destination.id }) else { return }
        await select(current, forceRefresh: true)
    }

    public func feedState(for destination: ReaderDestination) -> FeedLoadState {
        feedStates[destination] ?? .initialLoading
    }

    public func loadedPage(for destination: ReaderDestination) -> Int {
        loadedPages[destination, default: 0]
    }

    public func canLoadNextPage(for destination: ReaderDestination) -> Bool {
        guard case .loaded = feedState(for: destination) else { return false }
        return selectedDestination?.id == destination.id
            && destinationsWithMorePages.contains(destination)
            && loadedPages[destination, default: 0] < Self.maximumPage
    }

    public func loadNextPage(for destination: ReaderDestination) async {
        guard canLoadNextPage(for: destination),
              pagingDestinations.insert(destination).inserted else { return }
        defer { pagingDestinations.remove(destination) }

        let generation = feedGeneration
        let currentPage = loadedPages[destination, default: 1]
        let nextPage = currentPage + 1
        do {
            let envelope = try await fetchFeed(destination, page: nextPage)
            guard feedGeneration == generation,
                  selectedDestination?.id == destination.id,
                  loadedPages[destination] == currentPage,
                  !Task.isCancelled else { return }
            var rows = feedCache[destination] ?? []
            var ids = Set(rows.map(\.presentationID))
            rows.append(contentsOf: envelope.results.filter { ids.insert($0.presentationID).inserted })
            feedCache[destination] = rows
            feedStates[destination] = .loaded(rows)
            loadedPages[destination] = nextPage
            updateHasMorePages(for: destination, resultCount: envelope.results.count)
        } catch is CancellationError {
            return
        } catch {
            guard feedGeneration == generation,
                  selectedDestination?.id == destination.id,
                  !Task.isCancelled else { return }
            destinationsWithMorePages.remove(destination)
            feedStates[destination] = .failed(rows: feedCache[destination] ?? [], message: String(describing: error))
        }
    }

    public func preloadNextSubject(in orderedDestinations: [ReaderDestination]? = nil) async {
        let destinations = orderedDestinations ?? parentDestinations
        guard let selectedDestination,
              let index = destinations.firstIndex(where: { $0.id == selectedDestination.id }),
              destinations.indices.contains(index + 1) else {
            cancelPreloads()
            return
        }
        let destination = destinations[index + 1]
        guard feedCache[destination] == nil else {
            cancelPreloads()
            return
        }
        cancelPreloads(except: destination)

        let preload = preloadTasks[destination] ?? Preload(task: makePreloadTask(for: destination))
        preloadTasks[destination] = preload
        if let envelope = await preload.task.value,
           preloadTasks[destination]?.id == preload.id,
           !preload.task.isCancelled,
           feedCache[destination] == nil {
            cacheFirstPage(envelope, for: destination)
        }
        if preloadTasks[destination]?.id == preload.id {
            preloadTasks[destination] = nil
        }
    }

    private func loadTaxonomy(refresh: Bool, initial: Bool) async {
        taxonomyTask?.cancel()
        taxonomyGeneration &+= 1
        let generation = taxonomyGeneration
        let priorState = stableTaxonomyState
        taxonomyState = initial ? .initialLoading : .refreshing
        let cache = taxonomyCache

        let task = Task { @MainActor [weak self] in
            do {
                let envelope = try await (refresh ? cache.refresh() : cache.load())
                guard let self, self.taxonomyGeneration == generation, !Task.isCancelled else { return }
                await self.applyTaxonomy(envelope, generation: generation)
            } catch is CancellationError {
                if let self, self.taxonomyGeneration == generation {
                    self.taxonomyState = priorState
                }
                return
            } catch {
                guard let self, self.taxonomyGeneration == generation else { return }
                if Task.isCancelled {
                    self.taxonomyState = priorState
                    return
                }
                self.taxonomyState = .failed(message: String(describing: error))
            }
        }
        taxonomyTask = task
        await awaitTask(task)
        if taxonomyGeneration == generation {
            taxonomyTask = nil
        }
    }

    private func applyTaxonomy(_ envelope: NavigationEnvelope, generation: UInt64) async {
        guard taxonomyGeneration == generation else { return }
        preloadTasks.values.forEach { $0.task.cancel() }
        preloadTasks.removeAll()
        if envelope.version == "v2" {
            await applyFlatTaxonomy(envelope)
            return
        }
        let filtered = TaxonomyFilter.launchEligible(envelope)
        taxonomy = filtered
        parentDestinations = filtered.subjectAreas.map { .all(parent: $0) }

        guard let firstParent = filtered.subjectAreas.first else {
            taxonomyState = .emptyTaxonomy
            selectedDestination = nil
            childDestinations = []
            cancelFeedLane()
            unselectedFeedState = .empty
            return
        }

        let previous = selectedDestination
        let destination = preservedDestination(previous, in: filtered) ?? .all(parent: firstParent)
        taxonomyState = .loaded
        await select(destination)
    }

    public private(set) var forYouEligible = false

    public func setForYouEligible(_ eligible: Bool) async {
        guard forYouEligible != eligible else { return }
        forYouEligible = eligible
        feedCache[.forYou] = nil
        feedStates[.forYou] = nil
        if let task = preloadTasks.removeValue(forKey: .forYou) { task.task.cancel() }
        guard taxonomy?.version == "v2" else { return }
        parentDestinations.removeAll { $0 == .forYou }
        if eligible { parentDestinations.insert(.forYou, at: 0) }
        if !eligible, selectedDestination == .forYou {
            await select(.main)
        }
    }

    private func applyFlatTaxonomy(_ envelope: NavigationEnvelope) async {
        taxonomy = envelope
        parentDestinations = (forYouEligible ? [.forYou, .main] : [.main]) + envelope.subjectAreas
            .filter { $0.topicCount >= 5 }
            .map { .all(parent: $0) } + discoveredFeeds
        childDestinations = []

        let previousID = selectedDestination?.id
        let destination = parentDestinations.first(where: { $0.id == previousID })
            ?? parentDestinations[0]
        taxonomyState = .loaded
        await select(destination)
    }

    private func preservedDestination(
        _ previous: ReaderDestination?,
        in taxonomy: NavigationEnvelope
    ) -> ReaderDestination? {
        guard let previous,
              let parentSlug = previous.parentSlug,
              let parent = taxonomy.subjectAreas.first(where: { $0.slug == parentSlug }) else { return nil }
        switch previous {
        case .main, .forYou, .discovered:
            return nil
        case .all:
            return .all(parent: parent)
        case let .child(_, oldChild):
            guard let subject = parent.subjects.first(where: { $0.slug == oldChild.slug }) else { return nil }
            return .child(parent: parent, subject: subject)
        }
    }

    private func select(_ destination: ReaderDestination, forceRefresh: Bool = false) async {
        selectedDestination = destination
        updateChildDestinations(for: destination.parentSlug)

        if !forceRefresh, let preload = preloadTasks[destination] {
            if let envelope = await preload.task.value,
               preloadTasks[destination]?.id == preload.id,
               !preload.task.isCancelled,
               feedCache[destination] == nil {
                cacheFirstPage(envelope, for: destination)
            }
            if preloadTasks[destination]?.id == preload.id {
                preloadTasks[destination] = nil
            }
            guard selectedDestination?.id == destination.id else { return }
        }

        feedTask?.cancel()
        feedGeneration &+= 1
        let generation = feedGeneration
        let destinationID = destination.id

        if !forceRefresh, let cached = feedCache[destination] {
            feedStates[destination] = cached.isEmpty ? .empty : .loaded(cached)
            return
        }

        let cachedRows = feedCache[destination]
        let staleRows = forceRefresh ? (cachedRows ?? feedState(for: destination).rows) : []
        feedStates[destination] = forceRefresh && cachedRows != nil
            ? .refreshing(staleRows)
            : (staleRows.isEmpty ? .initialLoading : .refreshing(staleRows))
        let apiClient = self.apiClient

        let task = Task { @MainActor [weak self] in
            do {
                let envelope = try await Self.fetchFeed(apiClient, destination: destination, page: 1)
                let rows = Array(envelope.results.prefix(Self.pageSize))
                guard let self,
                      self.feedGeneration == generation,
                      self.selectedDestination?.id == destinationID,
                      !Task.isCancelled else { return }
                self.feedCache[destination] = rows
                self.feedStates[destination] = rows.isEmpty ? .empty : .loaded(rows)
                self.loadedPages[destination] = 1
                self.updateHasMorePages(for: destination, resultCount: envelope.results.count)
            } catch is CancellationError {
                guard let self,
                      self.feedGeneration == generation,
                      self.selectedDestination?.id == destinationID else { return }
                if let cached = self.feedCache[destination] {
                    self.feedStates[destination] = cached.isEmpty ? .empty : .loaded(cached)
                } else {
                    self.feedStates[destination] = .initialLoading
                }
                return
            } catch {
                guard let self,
                      self.feedGeneration == generation,
                      self.selectedDestination?.id == destinationID else { return }
                if Task.isCancelled {
                    if let cached = self.feedCache[destination] {
                        self.feedStates[destination] = cached.isEmpty ? .empty : .loaded(cached)
                    } else {
                        self.feedStates[destination] = .initialLoading
                    }
                    return
                }
                self.feedStates[destination] = .failed(rows: staleRows, message: String(describing: error))
            }
        }
        feedTask = task
        await awaitTask(task)
        if feedGeneration == generation {
            feedTask = nil
        }
    }

    private func fetchFeed(_ destination: ReaderDestination, page: Int) async throws -> TopicFeedEnvelope {
        try await Self.fetchFeed(apiClient, destination: destination, page: page)
    }

    private static func fetchFeed(
        _ apiClient: any APIClientProtocol,
        destination: ReaderDestination,
        page: Int
    ) async throws -> TopicFeedEnvelope {
        switch destination {
        case let .discovered(feed):
            try await apiClient.fetchDiscoveredTopics(feed: feed, page: page)
        case .forYou:
            try await apiClient.fetchForYouTopics(page: page)
        case .main:
            try await apiClient.fetchMainTopics(page: page)
        case let .all(parent):
            try await apiClient.fetchParentTopics(slug: parent.slug, page: page)
        case let .child(_, subject):
            try await apiClient.fetchChildTopics(slug: subject.slug, page: page)
        }
    }

    private func makePreloadTask(for destination: ReaderDestination) -> Task<TopicFeedEnvelope?, Never> {
        let apiClient = self.apiClient
        return Task {
            try? await Self.fetchFeed(apiClient, destination: destination, page: 1)
        }
    }

    private func cancelPreloads(except destination: ReaderDestination? = nil) {
        let stalePreloads = preloadTasks.filter { $0.key != destination }
        stalePreloads.values.forEach { $0.task.cancel() }
        stalePreloads.keys.forEach { preloadTasks[$0] = nil }
    }

    private func cacheFirstPage(_ envelope: TopicFeedEnvelope, for destination: ReaderDestination) {
        let rows = Array(envelope.results.prefix(Self.pageSize))
        feedCache[destination] = rows
        feedStates[destination] = rows.isEmpty ? .empty : .loaded(rows)
        loadedPages[destination] = 1
        updateHasMorePages(for: destination, resultCount: envelope.results.count)
    }

    private func updateHasMorePages(for destination: ReaderDestination, resultCount: Int) {
        if resultCount == Self.pageSize, loadedPages[destination, default: 0] < Self.maximumPage {
            destinationsWithMorePages.insert(destination)
        } else {
            destinationsWithMorePages.remove(destination)
        }
    }

    private func updateChildDestinations(for parentSlug: String?) {
        if taxonomy?.version == "v2" {
            childDestinations = []
            return
        }
        guard let parentSlug,
              let parent = taxonomy?.subjectAreas.first(where: { $0.slug == parentSlug }) else {
            childDestinations = []
            return
        }
        childDestinations = [.all(parent: parent)] + parent.subjects.map { .child(parent: parent, subject: $0) }
    }

    private func cancelFeedLane() {
        feedTask?.cancel()
        feedTask = nil
        feedGeneration &+= 1
    }

    private var stableTaxonomyState: TaxonomyLoadState {
        guard taxonomyState == .refreshing else { return taxonomyState }
        guard let taxonomy else { return .initialLoading }
        return taxonomy.subjectAreas.isEmpty ? .emptyTaxonomy : .loaded
    }

    private func clampedIndex(
        from index: Int,
        direction: ReaderNavigationDirection,
        count: Int
    ) -> Int {
        guard count > 0 else { return index }
        switch direction {
        case .previous: return max(0, index - 1)
        case .next: return min(count - 1, index + 1)
        }
    }

    private func awaitTask(_ task: Task<Void, Never>) async {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
