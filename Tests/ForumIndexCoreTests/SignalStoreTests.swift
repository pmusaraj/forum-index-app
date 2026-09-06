import XCTest
@testable import ForumIndexCore

@MainActor
final class SignalStoreTests: XCTestCase {
    func testPublicEnrollmentTrimsNameStoresRawTokenAndExposesStatus() async {
        let api = SignalAPISpy()
        let tokens = MemorySignalTokenStore()
        let store = SignalStore(
            apiClient: api,
            tokenStore: tokens,
            deviceCheckToken: { "AQID" }
        )

        await store.enroll(displayName: "  Penar  ", deviceName: "iPhone")

        XCTAssertTrue(store.isEnrolled)
        XCTAssertEqual(tokens.token, "raw-token")
        let enrollments = await api.enrollments
        XCTAssertEqual(enrollments, [.init(displayName: "Penar", deviceName: "iPhone", deviceCheckToken: "AQID")])
        XCTAssertEqual(store.installation?.publicID, "A7K-29Q")
        XCTAssertFalse(store.installation?.trusted ?? true)
        XCTAssertNil(store.enrollmentError)
    }

    func testDeviceCheckFailureDoesNotBlockPublicEnrollment() async {
        let api = SignalAPISpy()
        let store = SignalStore(
            apiClient: api,
            tokenStore: MemorySignalTokenStore(),
            deviceCheckToken: { throw TestError.failed }
        )

        await store.enroll(displayName: "Penar", deviceName: "Mac")

        XCTAssertTrue(store.isEnrolled)
        let enrollments = await api.enrollments
        XCTAssertEqual(enrollments, [.init(displayName: "Penar", deviceName: "Mac", deviceCheckToken: nil)])
    }

    func testEnrollmentValidatesTrimmedRequiredNameAndHundredCharacterLimit() async {
        let api = SignalAPISpy()
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore())

        await store.enroll(displayName: "   ", deviceName: "Mac")
        XCTAssertEqual(store.enrollmentError, "Enter a display name.")
        await store.enroll(displayName: String(repeating: "a", count: 101), deviceName: "Mac")
        XCTAssertEqual(store.enrollmentError, "Display name must be 100 characters or fewer.")
        let enrollments = await api.enrollments
        XCTAssertTrue(enrollments.isEmpty)
    }

    func testRefreshInstallationUpdatesTrustStatus() async {
        let api = SignalAPISpy(status: .init(
            publicID: "A7K-29Q", displayName: "Penar", deviceName: "Mac", deviceVerified: false, trusted: true
        ))
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore(token: "raw-token"))

        await store.refreshInstallation()

        XCTAssertTrue(store.installation?.trusted ?? false)
        let statusTokens = await api.statusTokens
        XCTAssertEqual(statusTokens, ["raw-token"])
    }

    func testInvalidCredentialDuringRefreshClearsEnrollment() async {
        let api = SignalAPISpy(statusError: .invalidBearerToken)
        let tokens = MemorySignalTokenStore(token: "raw-token")
        let store = SignalStore(apiClient: api, tokenStore: tokens)

        await store.refreshInstallation()

        XCTAssertFalse(store.isEnrolled)
        XCTAssertNil(tokens.token)
        XCTAssertNil(store.installation)
    }

    func testRemovingEnrollmentDuringRefreshDoesNotRestoreInstallation() async {
        let api = SignalAPISpy(pausesStatus: true)
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore(token: "raw-token"))

        let refresh = Task { await store.refreshInstallation() }
        await api.waitForStatusRequest()
        store.removeEnrollment()
        await api.completeStatusRequest()
        await refresh.value

        XCTAssertFalse(store.isEnrolled)
        XCTAssertNil(store.installation)
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

    func testInvalidCredentialDuringSignalClearsEnrollment() async {
        let api = SignalAPISpy()
        let tokens = MemorySignalTokenStore(token: "raw-token")
        let store = SignalStore(apiClient: api, tokenStore: tokens)

        let task = Task { await store.toggleSignal(topicID: 7, value: 1) }
        await api.waitForSignalCount(1)
        await api.failSignal(1, error: ForumIndexAPIError.invalidBearerToken)
        await task.value

        XCTAssertFalse(store.isEnrolled)
        XCTAssertNil(tokens.token)
        XCTAssertEqual(store.signalValue(for: 7), 0)
    }

    func testStaleSignalRejectionDoesNotDeleteReplacementEnrollment() async {
        let api = SignalAPISpy(enrollmentToken: "new-token")
        let tokens = MemorySignalTokenStore(token: "old-token")
        let store = SignalStore(apiClient: api, tokenStore: tokens)

        let oldSignal = Task { await store.toggleSignal(topicID: 7, value: 1) }
        await api.waitForSignalCount(1)
        store.removeEnrollment()
        await store.enroll(displayName: "Penar", deviceName: "iPhone")
        await api.failSignal(1, error: ForumIndexAPIError.invalidBearerToken)
        await oldSignal.value

        XCTAssertTrue(store.isEnrolled)
        XCTAssertEqual(tokens.token, "new-token")
    }

    func testAutomaticEnrollmentFailureAppearsOnTopic() async {
        let api = SignalAPISpy(enrollmentError: TestError.failed)
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore())

        await store.toggleSignal(topicID: 7, value: 1, deviceName: "iPhone")

        XCTAssertEqual(store.signalError(for: 7), "Couldn’t enable contributions. Try again.")
    }

    func testNoTokenMeansNoSignalRequest() async {
        let api = SignalAPISpy()
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore())

        await store.toggleSignal(topicID: 7, value: 1)

        XCTAssertFalse(store.isEnrolled)
        let signals = await api.signals
        XCTAssertTrue(signals.isEmpty)
    }

    func testFirstSignalAutomaticallyEnrollsDeviceAndSubmitsSignal() async {
        let api = SignalAPISpy()
        let tokens = MemorySignalTokenStore()
        let store = SignalStore(
            apiClient: api,
            tokenStore: tokens,
            deviceCheckToken: { "AQID" }
        )

        let task = Task { await store.toggleSignal(topicID: 7, value: 1, deviceName: "iPhone") }
        await api.waitForSignalCount(1)
        await api.completeSignal(1)
        await task.value

        XCTAssertTrue(store.isEnrolled)
        XCTAssertEqual(tokens.token, "raw-token")
        let enrollments = await api.enrollments
        XCTAssertEqual(enrollments, [.init(displayName: "Anonymous", deviceName: "iPhone", deviceCheckToken: "AQID")])
        let signals = await api.signals
        XCTAssertEqual(signals, [.init(topicID: 7, value: 1, token: "raw-token")])
    }

    func testActionsReportOnlyWhileAlreadyEnrolled() async {
        let api = SignalAPISpy()
        let unenrolled = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore())
        await unenrolled.reportAction(topicID: 7, action: "starred", active: true)
        let initialActions = await api.actions
        let initialEnrollments = await api.enrollments
        XCTAssertTrue(initialActions.isEmpty)
        XCTAssertTrue(initialEnrollments.isEmpty)

        let enrolled = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore(token: "raw-token"))
        await enrolled.reportAction(topicID: 7, action: "starred", active: false)
        await enrolled.reportAction(topicID: 7, action: "read", active: true)
        await enrolled.reportAction(topicID: 7, action: "low_quality", active: true)
        await enrolled.reportAction(topicID: 7, action: "inappropriate", active: true)

        let actions = await api.actions
        XCTAssertEqual(actions, [
            .init(topicID: 7, action: "starred", active: false, token: "raw-token"),
            .init(topicID: 7, action: "read", active: true, token: "raw-token"),
            .init(topicID: 7, action: "low_quality", active: true, token: "raw-token"),
            .init(topicID: 7, action: "inappropriate", active: true, token: "raw-token")
        ])
    }

    func testActionFailureIsBestEffortAndExposedInSettings() async {
        let api = SignalAPISpy(actionError: TestError.failed)
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore(token: "raw-token"))

        let error = await store.reportAction(topicID: 7, action: "starred", active: true)

        XCTAssertTrue(store.isEnrolled)
        XCTAssertEqual(error, "Couldn’t report this contribution.")
        XCTAssertEqual(store.contributionError, "Couldn’t report this contribution.")
    }

    func testActionsForOneTopicAreSentInLocalChangeOrder() async {
        let api = SignalAPISpy(pausesAction: true)
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore(token: "raw-token"))

        let add = Task { await store.reportAction(topicID: 7, action: "starred", active: true) }
        await api.waitForActionCount(1)
        let remove = Task { await store.reportAction(topicID: 7, action: "starred", active: false) }
        try? await Task.sleep(for: .milliseconds(50))
        let beforeFirstCompletion = await api.actions
        XCTAssertEqual(beforeFirstCompletion.map(\.active), [true])

        await api.completeActionRequest(1)
        await api.waitForActionCount(2)
        await api.completeActionRequest(2)
        await add.value
        await remove.value

        let actions = await api.actions
        XCTAssertEqual(actions.map(\.active), [true, false])
    }

    func testInvalidActionCredentialClearsMatchingEnrollment() async {
        let tokens = MemorySignalTokenStore(token: "raw-token")
        let store = SignalStore(
            apiClient: SignalAPISpy(actionError: ForumIndexAPIError.invalidBearerToken),
            tokenStore: tokens
        )

        await store.reportAction(topicID: 7, action: "read", active: true)

        XCTAssertFalse(store.isEnrolled)
        XCTAssertNil(tokens.token)
    }

    func testStaleActionRejectionDoesNotClearReplacementEnrollment() async {
        let api = SignalAPISpy(
            enrollmentToken: "new-token",
            actionError: ForumIndexAPIError.invalidBearerToken,
            pausesAction: true
        )
        let tokens = MemorySignalTokenStore(token: "old-token")
        let store = SignalStore(apiClient: api, tokenStore: tokens)

        let oldAction = Task { await store.reportAction(topicID: 7, action: "read", active: true) }
        await api.waitForActionRequest()
        store.removeEnrollment()
        await store.enroll(displayName: "Penar", deviceName: "iPhone")
        await api.completeActionRequest()
        await oldAction.value

        XCTAssertTrue(store.isEnrolled)
        XCTAssertEqual(tokens.token, "new-token")
    }

    func testOptOutRevokesBeforeClearingLocalEnrollment() async {
        let api = SignalAPISpy()
        let tokens = MemorySignalTokenStore(token: "raw-token")
        let store = SignalStore(apiClient: api, tokenStore: tokens)

        await store.optOut()

        let revokedTokens = await api.revokedTokens
        XCTAssertEqual(revokedTokens, ["raw-token"])
        XCTAssertFalse(store.isEnrolled)
        XCTAssertNil(tokens.token)
        XCTAssertNil(store.contributionError)
    }

    func testFailedOptOutKeepsEnrollmentAndShowsError() async {
        let api = SignalAPISpy(revokeError: TestError.failed)
        let tokens = MemorySignalTokenStore(token: "raw-token")
        let store = SignalStore(apiClient: api, tokenStore: tokens)

        await store.optOut()

        XCTAssertTrue(store.isEnrolled)
        XCTAssertEqual(tokens.token, "raw-token")
        XCTAssertEqual(store.contributionError, "Couldn’t opt out. Try again.")
    }

    func testInvalidCredentialDuringOptOutStillClearsEnrollment() async {
        let tokens = MemorySignalTokenStore(token: "raw-token")
        let store = SignalStore(
            apiClient: SignalAPISpy(revokeError: ForumIndexAPIError.invalidBearerToken),
            tokenStore: tokens
        )

        await store.optOut()

        XCTAssertFalse(store.isEnrolled)
        XCTAssertNil(tokens.token)
    }

    func testBusyStatePreventsDuplicateOptOut() async {
        let api = SignalAPISpy(pausesRevoke: true)
        let store = SignalStore(apiClient: api, tokenStore: MemorySignalTokenStore(token: "raw-token"))

        let first = Task { await store.optOut() }
        await api.waitForRevokeRequest()
        XCTAssertTrue(store.isEnrolling)
        await store.optOut()
        let revokedBeforeCompletion = await api.revokedTokens
        XCTAssertEqual(revokedBeforeCompletion, ["raw-token"])
        await api.completeRevokeRequest()
        await first.value

        XCTAssertFalse(store.isEnrolling)
        XCTAssertFalse(store.isEnrolled)
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
    struct Enrollment: Equatable {
        let displayName: String
        let deviceName: String
        let deviceCheckToken: String?
    }
    struct Request: Equatable {
        let topicID: Int
        let value: Int
        let token: String
    }
    struct ActionRequest: Equatable {
        let topicID: Int
        let action: String
        let active: Bool
        let token: String
    }

    private let status: SignalInstallation
    private let statusError: ForumIndexAPIError?
    private let pausesStatus: Bool
    private let enrollmentToken: String
    private let enrollmentError: (any Error)?
    private let actionError: (any Error)?
    private let revokeError: (any Error)?
    private let pausesAction: Bool
    private let pausesRevoke: Bool
    private(set) var inviteCodes: [String] = []
    private(set) var enrollments: [Enrollment] = []
    private(set) var statusTokens: [String] = []
    private(set) var signals: [Request] = []
    private(set) var actions: [ActionRequest] = []
    private(set) var revokedTokens: [String] = []
    private var signalContinuations: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var signalWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var statusContinuation: CheckedContinuation<Void, Never>?
    private var statusWaiters: [CheckedContinuation<Void, Never>] = []
    private var actionContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var actionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var revokeContinuation: CheckedContinuation<Void, Never>?
    private var revokeWaiters: [CheckedContinuation<Void, Never>] = []

    init(status: SignalInstallation = .init(
        publicID: "A7K-29Q", displayName: "Penar", deviceName: "iPhone", deviceVerified: true, trusted: false
    ), statusError: ForumIndexAPIError? = nil, pausesStatus: Bool = false,
       enrollmentToken: String = "raw-token", enrollmentError: (any Error)? = nil,
       actionError: (any Error)? = nil, revokeError: (any Error)? = nil,
       pausesAction: Bool = false, pausesRevoke: Bool = false) {
        self.status = status
        self.statusError = statusError
        self.pausesStatus = pausesStatus
        self.enrollmentToken = enrollmentToken
        self.enrollmentError = enrollmentError
        self.actionError = actionError
        self.revokeError = revokeError
        self.pausesAction = pausesAction
        self.pausesRevoke = pausesRevoke
    }

    func enrollForSignals(inviteCode: String) async throws -> String {
        inviteCodes.append(inviteCode)
        return "raw-token"
    }

    func createInstallation(displayName: String, deviceName: String, deviceCheckToken: String?) async throws -> SignalEnrollment {
        enrollments.append(.init(displayName: displayName, deviceName: deviceName, deviceCheckToken: deviceCheckToken))
        if let enrollmentError { throw enrollmentError }
        return SignalEnrollment(token: enrollmentToken, installation: status)
    }

    func fetchInstallation(bearerToken: String) async throws -> SignalInstallation {
        statusTokens.append(bearerToken)
        statusWaiters.forEach { $0.resume() }
        statusWaiters.removeAll()
        if pausesStatus {
            await withCheckedContinuation { statusContinuation = $0 }
        }
        if let statusError { throw statusError }
        return status
    }

    func waitForStatusRequest() async {
        guard statusTokens.isEmpty else { return }
        await withCheckedContinuation { statusWaiters.append($0) }
    }

    func completeStatusRequest() {
        statusContinuation?.resume()
        statusContinuation = nil
    }

    func setSignal(topicID: Int, value: Int, bearerToken: String) async throws {
        signals.append(.init(topicID: topicID, value: value, token: bearerToken))
        let number = signals.count
        let ready = signalWaiters.filter { $0.0 <= number }
        signalWaiters.removeAll { $0.0 <= number }
        ready.forEach { $0.1.resume() }
        try await withCheckedThrowingContinuation { signalContinuations[number] = $0 }
    }

    func reportAction(topicID: Int, action: String, active: Bool, bearerToken: String) async throws {
        actions.append(.init(topicID: topicID, action: action, active: active, token: bearerToken))
        let number = actions.count
        let ready = actionWaiters.filter { $0.0 <= number }
        actionWaiters.removeAll { $0.0 <= number }
        ready.forEach { $0.1.resume() }
        if pausesAction { await withCheckedContinuation { actionContinuations[number] = $0 } }
        if let actionError { throw actionError }
    }

    func revokeInstallation(bearerToken: String) async throws {
        revokedTokens.append(bearerToken)
        revokeWaiters.forEach { $0.resume() }
        revokeWaiters.removeAll()
        if pausesRevoke { await withCheckedContinuation { revokeContinuation = $0 } }
        if let revokeError { throw revokeError }
    }

    func waitForActionRequest() async {
        await waitForActionCount(1)
    }

    func waitForActionCount(_ count: Int) async {
        guard actions.count < count else { return }
        await withCheckedContinuation { actionWaiters.append((count, $0)) }
    }

    func completeActionRequest(_ number: Int = 1) {
        actionContinuations.removeValue(forKey: number)?.resume()
    }

    func waitForRevokeRequest() async {
        guard revokedTokens.isEmpty else { return }
        await withCheckedContinuation { revokeWaiters.append($0) }
    }

    func completeRevokeRequest() {
        revokeContinuation?.resume()
        revokeContinuation = nil
    }

    func waitForSignalCount(_ count: Int) async {
        guard signals.count < count else { return }
        await withCheckedContinuation { signalWaiters.append((count, $0)) }
    }

    func completeSignal(_ number: Int) {
        signalContinuations.removeValue(forKey: number)?.resume()
    }

    func failSignal(_ number: Int, error: any Error = TestError.failed) {
        signalContinuations.removeValue(forKey: number)?.resume(throwing: error)
    }

}

private enum TestError: Error { case failed }
