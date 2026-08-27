import Foundation
import Observation

public protocol TaxonomyCacheProtocol: Sendable {
    func load() async throws -> NavigationEnvelope
    func refresh() async throws -> NavigationEnvelope
}

extension LaunchTaxonomyCache: TaxonomyCacheProtocol {}

public enum ReaderDestination: Hashable, Identifiable, Sendable {
    case main
    case all(parent: SubjectArea)
    case child(parent: SubjectArea, subject: ChildSubject)

    public var id: String {
        switch self {
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
        case .main: "main"
        case let .all(parent): parent.slug
        case let .child(_, subject): subject.slug
        }
    }

    public var parentSlug: String? {
        switch self {
        case .main: nil
        case let .all(parent), let .child(parent, _): parent.slug
        }
    }

    public var parentName: String {
        switch self {
        case .main: "Main"
        case let .all(parent), let .child(parent, _): parent.name
        }
    }

    public var label: String {
        switch self {
        case .main: "Main"
        case let .all(parent): "All \(parent.name)"
        case let .child(_, subject): subject.name
        }
    }

    public var isAll: Bool {
        switch self {
        case .main, .all: true
        case .child: false
        }
    }

    public static func == (lhs: ReaderDestination, rhs: ReaderDestination) -> Bool {
        switch (lhs, rhs) {
        case (.main, .main):
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
    public private(set) var taxonomyState: TaxonomyLoadState = .initialLoading
    public private(set) var taxonomy: NavigationEnvelope?
    public private(set) var parentDestinations: [ReaderDestination] = []
    public private(set) var childDestinations: [ReaderDestination] = []
    public private(set) var selectedDestination: ReaderDestination?
    public private(set) var feedState: FeedLoadState = .initialLoading

    private let apiClient: any APIClientProtocol
    private let taxonomyCache: any TaxonomyCacheProtocol
    private var feedCache: [ReaderDestination: [Topic]] = [:]
    private var taxonomyTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var taxonomyGeneration: UInt64 = 0
    private var feedGeneration: UInt64 = 0

    public init(apiClient: any APIClientProtocol, taxonomyCache: any TaxonomyCacheProtocol) {
        self.apiClient = apiClient
        self.taxonomyCache = taxonomyCache
    }

    public func launch() async {
        await loadTaxonomy(refresh: false, initial: true)
    }

    public func retryTaxonomy() async {
        let hasPriorTaxonomy = taxonomy != nil
        await loadTaxonomy(refresh: hasPriorTaxonomy, initial: !hasPriorTaxonomy)
    }

    public func refreshTaxonomy() async {
        await loadTaxonomy(refresh: true, initial: false)
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
            feedState = .empty
            return
        }

        let previous = selectedDestination
        let destination = preservedDestination(previous, in: filtered) ?? .all(parent: firstParent)
        taxonomyState = .loaded
        await select(destination)
    }

    private func applyFlatTaxonomy(_ envelope: NavigationEnvelope) async {
        taxonomy = envelope
        parentDestinations = [.main] + envelope.subjectAreas.map { .all(parent: $0) }
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
        case .main:
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

        feedTask?.cancel()
        feedGeneration &+= 1
        let generation = feedGeneration
        let destinationID = destination.id

        if !forceRefresh, let cached = feedCache[destination] {
            feedState = cached.isEmpty ? .empty : .loaded(cached)
            return
        }

        let cachedRows = feedCache[destination]
        let staleRows = forceRefresh ? (cachedRows ?? feedState.rows) : []
        feedState = forceRefresh && cachedRows != nil
            ? .refreshing(staleRows)
            : (staleRows.isEmpty ? .initialLoading : .refreshing(staleRows))
        let apiClient = self.apiClient

        let task = Task { @MainActor [weak self] in
            do {
                let envelope: TopicFeedEnvelope
                switch destination {
                case .main:
                    envelope = try await apiClient.fetchMainTopics()
                case let .all(parent):
                    envelope = try await apiClient.fetchParentTopics(slug: parent.slug)
                case let .child(_, subject):
                    envelope = try await apiClient.fetchChildTopics(slug: subject.slug)
                }
                let rows = Array(envelope.results.prefix(30))
                guard let self,
                      self.feedGeneration == generation,
                      self.selectedDestination?.id == destinationID,
                      !Task.isCancelled else { return }
                self.feedCache[destination] = rows
                self.feedState = rows.isEmpty ? .empty : .loaded(rows)
            } catch is CancellationError {
                guard let self,
                      self.feedGeneration == generation,
                      self.selectedDestination?.id == destinationID else { return }
                if let cached = self.feedCache[destination] {
                    self.feedState = cached.isEmpty ? .empty : .loaded(cached)
                } else {
                    self.feedState = .initialLoading
                }
                return
            } catch {
                guard let self,
                      self.feedGeneration == generation,
                      self.selectedDestination?.id == destinationID else { return }
                if Task.isCancelled {
                    if let cached = self.feedCache[destination] {
                        self.feedState = cached.isEmpty ? .empty : .loaded(cached)
                    } else {
                        self.feedState = .initialLoading
                    }
                    return
                }
                self.feedState = .failed(rows: staleRows, message: String(describing: error))
            }
        }
        feedTask = task
        await awaitTask(task)
        if feedGeneration == generation {
            feedTask = nil
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
