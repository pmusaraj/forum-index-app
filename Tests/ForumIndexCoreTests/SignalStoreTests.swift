import XCTest
@testable import ForumIndexCore

@MainActor
final class SignalStoreTests: XCTestCase {
    func testRequestPersistsTokenAndMovesPendingToApproved() async {
        let api = SignalAPISpy()
        let requests = MemorySignalTokenStore()
        let store = makeStore(api: api, requestTokens: requests)

        await store.requestAccess(name: "  Penar  ", deviceModel: "  iPhone18,2  ")
        XCTAssertEqual(store.accessRequestStatus, .pending)
        XCTAssertEqual(requests.token, "request-123")
        let accessRequests = await api.accessRequests
        XCTAssertEqual(accessRequests, [.init(name: "Penar", deviceModel: "iPhone18,2")])

        await api.setRequestStatus(.approved)
        await store.refreshAccessRequest()
        XCTAssertEqual(store.accessRequestStatus, .approved)
    }

    func testApprovedRequestRegistersThroughPasskeySeamAndStoresBearer() async {
        let api = SignalAPISpy()
        await api.setRequestStatus(.approved)
        let requests = MemorySignalTokenStore(token: "request-123")
        let bearers = MemorySignalTokenStore()
        let passkeys = PasskeyAuthorizerSpy()
        let store = makeStore(api: api, bearers: bearers, requestTokens: requests, passkeys: passkeys)
        await store.refreshAccessRequest()

        await store.enableWithPasskey()

        XCTAssertTrue(store.isEnrolled)
        XCTAssertEqual(bearers.token, "registered-bearer")
        XCTAssertNil(requests.token)
        XCTAssertEqual(passkeys.registrationOptions, [.fixture])
        let credentials = await api.registrationCredentials
        XCTAssertEqual(credentials, [.fixture])
    }

    func testRestoreUsesAssertionAndStoresRotatedBearer() async {
        let api = SignalAPISpy()
        let bearers = MemorySignalTokenStore()
        let passkeys = PasskeyAuthorizerSpy()
        let store = makeStore(api: api, bearers: bearers, passkeys: passkeys)

        await store.restoreWithPasskey()

        XCTAssertTrue(store.isEnrolled)
        XCTAssertEqual(bearers.token, "rotated-bearer")
        XCTAssertEqual(passkeys.authenticationOptions, [.fixture])
        let credentials = await api.authenticationCredentials
        XCTAssertEqual(credentials, [.fixture])
    }

    func testPasskeyCancellationIsNotShownAsAnError() async {
        let passkeys = PasskeyAuthorizerSpy(error: CancellationError())
        let store = makeStore(api: SignalAPISpy(), passkeys: passkeys)

        await store.restoreWithPasskey()

        XCTAssertNil(store.accessError)
        XCTAssertFalse(store.isEnrolled)
        XCTAssertFalse(store.isWorking)
    }

    func testDeclinedStateAllowsAReplacementRequest() async {
        let api = SignalAPISpy()
        await api.setRequestStatus(.declined)
        let store = makeStore(api: api, requestTokens: MemorySignalTokenStore(token: "old-request"))
        await store.refreshAccessRequest()
        XCTAssertEqual(store.accessRequestStatus, .declined)

        await store.requestAccess(name: "Penar", deviceModel: "Mac")

        XCTAssertEqual(store.accessRequestStatus, .pending)
        let requestCount = await api.accessRequests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testSignalIsOptimisticAndTapAgainClears() async {
        let api = SignalAPISpy()
        let defaults = cleanDefaults(#function)
        let store = makeStore(api: api, bearers: MemorySignalTokenStore(token: "raw-token"), defaults: defaults)

        let up = Task { await store.toggleSignal(topicID: 42, value: 1) }
        await api.waitForSignalCount(1)
        XCTAssertEqual(store.signalValue(for: 42), 1)
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
        XCTAssertNil(defaults.data(forKey: "topic-signal-values-v1"))
    }

    func testUnauthorizedSignalClearsBearerAndCacheAndRequiresPasskeyRestore() async throws {
        let api = SignalAPISpy()
        let bearers = MemorySignalTokenStore(token: "raw-token")
        let defaults = cleanDefaults(#function)
        defaults.set(try JSONEncoder().encode([7: 1]), forKey: "topic-signal-values-v1")
        let store = makeStore(api: api, bearers: bearers, defaults: defaults)

        let task = Task { await store.toggleSignal(topicID: 7, value: -1) }
        await api.waitForSignalCount(1)
        await api.rejectUnauthorizedSignal(1)
        await task.value

        XCTAssertFalse(store.isEnrolled)
        XCTAssertNil(bearers.token)
        XCTAssertEqual(store.signalValue(for: 7), 0)
        XCTAssertNil(defaults.data(forKey: "topic-signal-values-v1"))
        XCTAssertEqual(store.accessError, "Access expired. Restore access with your passkey in Settings.")
    }

    func testRemoveAccessKeepsPasskeyRestorableAndClearsLocalState() async throws {
        let bearers = MemorySignalTokenStore(token: "raw-token")
        let defaults = cleanDefaults(#function)
        defaults.set(try JSONEncoder().encode([7: 1]), forKey: "topic-signal-values-v1")
        let store = makeStore(api: SignalAPISpy(), bearers: bearers, defaults: defaults)

        store.removeAccess()

        XCTAssertNil(bearers.token)
        XCTAssertFalse(store.isEnrolled)
        XCTAssertNil(defaults.data(forKey: "topic-signal-values-v1"))
    }

    private func makeStore(
        api: SignalAPISpy,
        bearers: MemorySignalTokenStore = MemorySignalTokenStore(),
        requestTokens: MemorySignalTokenStore = MemorySignalTokenStore(),
        passkeys: PasskeyAuthorizerSpy = PasskeyAuthorizerSpy(),
        defaults: UserDefaults? = nil
    ) -> SignalStore {
        SignalStore(
            apiClient: api,
            tokenStore: bearers,
            requestTokenStore: requestTokens,
            passkeyAuthorizer: passkeys,
            defaults: defaults ?? cleanDefaults(UUID().uuidString)
        )
    }

    private func cleanDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private enum StoreTestError: Error { case failed }

private final class MemorySignalTokenStore: SignalTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedToken: String?

    init(token: String? = nil) { storedToken = token }
    var token: String? { lock.withLock { storedToken } }
    func readToken() throws -> String? { token }
    func saveToken(_ token: String) throws { lock.withLock { storedToken = token } }
    func deleteToken() throws { lock.withLock { storedToken = nil } }
}

@MainActor
private final class PasskeyAuthorizerSpy: PasskeyAuthorizing {
    private(set) var registrationOptions: [PasskeyRegistrationOptions] = []
    private(set) var authenticationOptions: [PasskeyAuthenticationOptions] = []
    private let error: Error?

    init(error: Error? = nil) { self.error = error }

    func register(options: PasskeyRegistrationOptions) async throws -> PasskeyRegistrationCredential {
        registrationOptions.append(options)
        if let error { throw error }
        return .fixture
    }

    func authenticate(options: PasskeyAuthenticationOptions) async throws -> PasskeyAuthenticationCredential {
        authenticationOptions.append(options)
        if let error { throw error }
        return .fixture
    }
}

private actor SignalAPISpy: SignalAPIClientProtocol {
    struct AccessRequest: Equatable { let name: String; let deviceModel: String }
    struct SignalRequest: Equatable { let topicID: Int; let value: Int; let token: String }

    private var status: SignalAccessRequestStatus = .pending
    private(set) var accessRequests: [AccessRequest] = []
    private(set) var registrationCredentials: [PasskeyRegistrationCredential] = []
    private(set) var authenticationCredentials: [PasskeyAuthenticationCredential] = []
    private(set) var signals: [SignalRequest] = []
    private var signalContinuations: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var signalWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func setRequestStatus(_ status: SignalAccessRequestStatus) { self.status = status }

    func requestSignalAccess(name: String, deviceModel: String) async throws -> SignalAccessRequest {
        accessRequests.append(.init(name: name, deviceModel: deviceModel))
        return .init(requestToken: "request-123", status: .pending)
    }

    func fetchSignalAccessRequest(requestToken: String) async throws -> SignalAccessRequest {
        .init(requestToken: requestToken, status: status)
    }

    func fetchPasskeyRegistrationOptions(requestToken: String) async throws -> PasskeyRegistrationOptions { .fixture }
    func registerPasskey(_ credential: PasskeyRegistrationCredential, requestToken: String) async throws -> String {
        registrationCredentials.append(credential)
        return "registered-bearer"
    }
    func fetchPasskeyAuthenticationOptions() async throws -> PasskeyAuthenticationOptions { .fixture }
    func authenticatePasskey(_ credential: PasskeyAuthenticationCredential, ceremonyToken: String) async throws -> String {
        authenticationCredentials.append(credential)
        return "rotated-bearer"
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
    func completeSignal(_ number: Int) { signalContinuations.removeValue(forKey: number)?.resume() }
    func rejectUnauthorizedSignal(_ number: Int) {
        signalContinuations.removeValue(forKey: number)?.resume(throwing: ForumIndexAPIError.httpStatus(401))
    }
}

private extension PasskeyRegistrationOptions {
    static let fixture = Self(
        challenge: "Y2hhbGxlbmdl",
        rp: .init(id: "do3.musaraj.com", name: "Forum Index"),
        user: .init(id: "dXNlcg", name: "Penar", displayName: "Penar"),
        excludeCredentials: []
    )
}
private extension PasskeyAuthenticationOptions {
    static let fixture = Self(
        challenge: "Y2hhbGxlbmdl",
        rpID: "do3.musaraj.com",
        allowCredentials: [],
        ceremonyToken: "ceremony-123"
    )
}
private extension PasskeyRegistrationCredential {
    static let fixture = Self(
        id: "credential-id",
        rawID: "cmF3LWlk",
        response: .init(clientDataJSON: "Y2xpZW50", attestationObject: "YXR0ZXN0YXRpb24")
    )
}
private extension PasskeyAuthenticationCredential {
    static let fixture = Self(
        id: "credential-id",
        rawID: "cmF3LWlk",
        response: .init(clientDataJSON: "Y2xpZW50", authenticatorData: "YXV0aA", signature: "c2ln", userHandle: "dXNlcg")
    )
}
