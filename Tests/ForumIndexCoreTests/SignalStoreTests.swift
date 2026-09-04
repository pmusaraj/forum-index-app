import XCTest
@testable import ForumIndexCore

@MainActor
final class SignalStoreTests: XCTestCase {
    func testEnrollmentStoresRawTokenAndEnablesSignals() async {
        let api = SignalAPISpy(enrollmentToken: "raw-token")
        let tokens = MemorySignalTokenStore()
        let store = SignalStore(apiClient: api, tokenStore: tokens)

        await store.enroll(inviteCode: "  invite-123  ")

        XCTAssertTrue(store.isEnrolled)
        XCTAssertEqual(tokens.token, "raw-token")
        let inviteCodes = await api.inviteCodes
        XCTAssertEqual(inviteCodes, ["invite-123"])
        XCTAssertNil(store.enrollmentError)
    }

    func testSignalIsOptimisticAndTapAgainClears() async {
        let api = SignalAPISpy()
        let tokens = MemorySignalTokenStore(token: "raw-token")
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = SignalStore(apiClient: api, tokenStore: tokens, defaults: defaults)

        let up = Task { await store.toggleSignal(topicID: 42, value: 1) }
        await api.waitForSignalCount(1)
        XCTAssertEqual(store.signalValue(for: 42), 1)
        XCTAssertTrue(store.isUpdating(topicID: 42))
        await api.completeSignal(1)
        await up.value

        let clear = Task { await store.toggleSignal(topicID: 42, value: 1) }
        await api.waitForSignalCount(2)
        XCTAssertEqual(store.signalValue(for: 42), 0)
        await api.completeSignal(2)
        await clear.value

        let signals = await api.signals
        XCTAssertEqual(signals, [
            .init(topicID: 42, value: 1, token: "raw-token"),
            .init(topicID: 42, value: 0, token: "raw-token")
        ])
        XCTAssertFalse(store.isUpdating(topicID: 42))

        let restored = SignalStore(apiClient: api, tokenStore: tokens, defaults: defaults)
        XCTAssertEqual(restored.signalValue(for: 42), 0)
    }

    func testSuccessfulSignalIsRestoredFromLocalCache() async {
        let api = SignalAPISpy()
        let tokens = MemorySignalTokenStore(token: "raw-token")
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = SignalStore(apiClient: api, tokenStore: tokens, defaults: defaults)

        let task = Task { await store.toggleSignal(topicID: 42, value: 1) }
        await api.waitForSignalCount(1)
        await api.completeSignal(1)
        await task.value

        let restored = SignalStore(apiClient: api, tokenStore: tokens, defaults: defaults)
        XCTAssertEqual(restored.signalValue(for: 42), 1)
    }

    func testFailedSignalRollsBackAndExposesError() async {
        let api = SignalAPISpy()
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore(token: "raw-token"))

        let task = Task { await store.toggleSignal(topicID: 7, value: -1) }
        await api.waitForSignalCount(1)
        XCTAssertEqual(store.signalValue(for: 7), -1)
        await api.failSignal(1)
        await task.value

        XCTAssertEqual(store.signalValue(for: 7), 0)
        XCTAssertEqual(store.signalError(for: 7), "Couldn’t save your signal. Try again.")
    }

    func testNoTokenMeansNoSignalRequest() async {
        let api = SignalAPISpy()
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore())

        await store.toggleSignal(topicID: 7, value: 1)

        XCTAssertFalse(store.isEnrolled)
        let signals = await api.signals
        XCTAssertTrue(signals.isEmpty)
    }
}

private final class MemorySignalTokenStore: SignalTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedToken: String?

    init(token: String? = nil) { storedToken = token }

    var token: String? { lock.withLock { storedToken } }
    func readToken() throws -> String? { token }
    func saveToken(_ token: String) throws { lock.withLock { storedToken = token } }
    func deleteToken() throws { lock.withLock { storedToken = nil } }
}

private actor SignalAPISpy: SignalAPIClientProtocol {
    struct Request: Equatable {
        let topicID: Int
        let value: Int
        let token: String
    }

    private let enrollmentToken: String
    private(set) var inviteCodes: [String] = []
    private(set) var signals: [Request] = []
    private var signalContinuations: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var signalWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(enrollmentToken: String = "raw-token") { self.enrollmentToken = enrollmentToken }

    func enrollForSignals(inviteCode: String) async throws -> String {
        inviteCodes.append(inviteCode)
        return enrollmentToken
    }

    func setSignal(topicID: Int, value: Int, bearerToken: String) async throws {
        signals.append(.init(topicID: topicID, value: value, token: bearerToken))
        let number = signals.count
        let ready = signalWaiters.filter { $0.0 <= number }
        signalWaiters.removeAll { $0.0 <= number }
        ready.forEach { $0.1.resume() }
        try await withCheckedThrowingContinuation { signalContinuations[number] = $0 }
    }

    func waitForSignalCount(_ count: Int) async {
        guard signals.count < count else { return }
        await withCheckedContinuation { signalWaiters.append((count, $0)) }
    }

    func completeSignal(_ number: Int) {
        signalContinuations.removeValue(forKey: number)?.resume()
    }

    func failSignal(_ number: Int) {
        signalContinuations.removeValue(forKey: number)?.resume(throwing: TestError.failed)
    }

    private enum TestError: Error { case failed }
}
