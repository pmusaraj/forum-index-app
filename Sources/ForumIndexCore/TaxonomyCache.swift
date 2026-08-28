import Foundation

public actor LaunchTaxonomyCache {
    private struct InFlightRequest {
        let generation: UInt64
        let task: Task<NavigationEnvelope, Error>
    }

    private struct Waiter {
        let generation: UInt64
        let continuation: CheckedContinuation<NavigationEnvelope, any Error>
    }

    private let apiClient: any APIClientProtocol
    private let onCoalescedLoad: (@Sendable () async -> Void)?
    private let onRequestCompletion: (@Sendable (UInt64) async -> Void)?
    private var cachedTaxonomy: NavigationEnvelope?
    private var inFlight: InFlightRequest?
    private var waiters: [UUID: Waiter] = [:]
    private var nextGeneration: UInt64 = 0

    public init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
        onCoalescedLoad = nil
        onRequestCompletion = nil
    }

    init(
        apiClient: any APIClientProtocol,
        onCoalescedLoad: @escaping @Sendable () async -> Void,
        onRequestCompletion: (@Sendable (UInt64) async -> Void)? = nil
    ) {
        self.apiClient = apiClient
        self.onCoalescedLoad = onCoalescedLoad
        self.onRequestCompletion = onRequestCompletion
    }

    public func load() async throws -> NavigationEnvelope {
        try Task.checkCancellation()
        if let cachedTaxonomy { return cachedTaxonomy }
        return try await fetchCoalescing()
    }

    public func refresh() async throws -> NavigationEnvelope {
        try Task.checkCancellation()
        return try await startFetch()
    }

    public func clear() {
        cachedTaxonomy = nil
        guard let request = inFlight else { return }

        inFlight = nil
        request.task.cancel()
        resumeWaiters(for: request.generation, with: .failure(CancellationError()))
    }

    private func fetchCoalescing() async throws -> NavigationEnvelope {
        if let inFlight {
            return try await awaitResult(of: inFlight, notifyCoalesced: true)
        }

        return try await startFetch()
    }

    private func startFetch() async throws -> NavigationEnvelope {
        inFlight?.task.cancel()
        let apiClient = self.apiClient
        let task = Task { try await apiClient.fetchTaxonomy() }
        nextGeneration &+= 1
        let request = InFlightRequest(generation: nextGeneration, task: task)
        inFlight = request

        Task { [weak self] in
            let result = await task.result
            await self?.complete(result, generation: request.generation)
        }
        return try await awaitResult(of: request)
    }

    private func awaitResult(
        of request: InFlightRequest,
        notifyCoalesced: Bool = false
    ) async throws -> NavigationEnvelope {
        try Task.checkCancellation()
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[waiterID] = Waiter(generation: request.generation, continuation: continuation)
                if notifyCoalesced {
                    Task { await onCoalescedLoad?() }
                }
                if Task.isCancelled {
                    cancelWaiter(waiterID)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    private func cancelWaiter(_ waiterID: UUID) {
        waiters.removeValue(forKey: waiterID)?.continuation.resume(throwing: CancellationError())
    }

    private func complete(
        _ result: Result<NavigationEnvelope, any Error>,
        generation: UInt64
    ) async {
        if inFlight?.generation == generation {
            if case let .success(taxonomy) = result {
                cachedTaxonomy = taxonomy
            }
            inFlight = nil
        }
        resumeWaiters(for: generation, with: result)
        await onRequestCompletion?(generation)
    }

    private func resumeWaiters(
        for generation: UInt64,
        with result: Result<NavigationEnvelope, any Error>
    ) {
        let matchingWaiters = waiters.filter { $0.value.generation == generation }
        matchingWaiters.keys.forEach { waiters.removeValue(forKey: $0) }
        matchingWaiters.values.forEach { $0.continuation.resume(with: result) }
    }
}

public enum TaxonomyFilter {
    public static func launchEligible(_ envelope: NavigationEnvelope, minimumTopicCount: Int = 10) -> NavigationEnvelope {
        NavigationEnvelope(
            window: envelope.window,
            subjectAreas: envelope.subjectAreas.compactMap { area in
                guard area.topicCount >= minimumTopicCount else { return nil }
                return SubjectArea(
                    id: area.id,
                    name: area.name,
                    slug: area.slug,
                    topicCount: area.topicCount,
                    subjects: area.subjects.filter { $0.topicCount >= minimumTopicCount },
                    description: area.description,
                    position: area.position,
                    secondary: area.secondary
                )
            }
        )
    }
}

public enum ExcerptNormalizer {
    public static func plainText(_ html: String?) -> String? {
        guard var text = html, !text.isEmpty else { return nil }

        text = text.replacingOccurrences(
            of: #"(?i)</?(?:p|div|br|li|ul|ol|h[1-6]|blockquote)[^>]*>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
        text = decodeEntities(in: text)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func decodeEntities(in string: String) -> String {
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " "
        ]
        let pattern = #"&(?:#([0-9]+)|#[xX]([0-9A-Fa-f]+)|([A-Za-z]+));"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let matches = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
        var result = string
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let replacement: String?
            if match.range(at: 1).location != NSNotFound,
               let digitRange = Range(match.range(at: 1), in: result),
               let scalar = UInt32(result[digitRange]).flatMap(UnicodeScalar.init) {
                replacement = String(Character(scalar))
            } else if match.range(at: 2).location != NSNotFound,
                      let hexRange = Range(match.range(at: 2), in: result),
                      let scalar = UInt32(result[hexRange], radix: 16).flatMap(UnicodeScalar.init) {
                replacement = String(Character(scalar))
            } else if match.range(at: 3).location != NSNotFound,
                      let nameRange = Range(match.range(at: 3), in: result) {
                replacement = named[String(result[nameRange]).lowercased()]
            } else {
                replacement = nil
            }
            if let replacement { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }
}
